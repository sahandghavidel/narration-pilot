import Combine
import Foundation

struct GuidedNarrationDraft: Codable, Equatable, Sendable {
    var sessionID: UUID
    var sceneID: String
    var revision: Int
    var narration: String
}

struct GuidedNarrationDecision: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var id: UUID
    var kind: String
    var draft: GuidedNarrationDraft
    var createdAt: Date
}

struct GuidedNarrationCommand: Codable, Sendable {
    var schemaVersion = 1
    var createdAt = Date()
    var id: UUID
    var sessionID: UUID
    var kind: String
    var draft: GuidedNarrationDraft?
    var eventID: UUID?
    var nextCandidate: GuidedNarrationDraft?
}

struct GuidedAudioVoice: Codable, Equatable, Sendable {
    var id: String
    var name: String
}

struct GuidedPreparedAudio: Equatable, Sendable {
    var versionID: UUID
    var duration: Double
}

struct GuidedAudioReview: Codable, Equatable, Sendable {
    var voice: GuidedAudioVoice
    var attempt: Int
    var versionID: UUID?
    var duration: Double?
}

struct GuidedAudioDecision: Codable, Sendable {
    var schemaVersion = 1
    var id: UUID
    var kind = "approveAudio"
    var draft: GuidedNarrationDraft
    var audio: GuidedAudioReview
    var createdAt: Date
}

struct GuidedNarrationSnapshot: Codable {
    var schemaVersion = 1
    var appRunning: Bool
    var pid: Int32
    var updatedAt: Date
    var active: Bool
    var phase: String
    var message: String
    var draft: GuidedNarrationDraft?
    var decision: GuidedNarrationDecision?
    var acknowledged: Bool
    var speechActive: Bool
    var audioReview: GuidedAudioReview?
    var audioDecision: GuidedAudioDecision?
    var audioAcknowledged: Bool?
    var audioBusy: Bool?
    var pendingEndingSessionID: UUID?
    var firstWordAfterPauseMilliseconds: Double?
    var nextCandidate: GuidedNarrationDraft?
    var remainingChapterScenes: [GuidedNarrationDraft]?
    var practice: [String: String]?
}

/// Local guided wording/audio handshake. Frozen wording is passed directly to
/// the existing cloned-audio service; it never touches the system clipboard,
/// starts recording, or changes the existing macOS speech controller.
@MainActor
final class GuidedNarrationReview: ObservableObject {
    nonisolated static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/local.clipboardreadermac/GuidedNarrationReview")
    @Published private(set) var active = false
    @Published private(set) var phase = "inactive"
    @Published private(set) var message = "No guided narration review is active."
    @Published private(set) var draft: GuidedNarrationDraft?
    @Published private(set) var decision: GuidedNarrationDecision?
    @Published private(set) var acknowledged = false
    @Published private(set) var audioReview: GuidedAudioReview?
    @Published private(set) var audioDecision: GuidedAudioDecision?
    @Published private(set) var audioAcknowledged = false
    @Published private(set) var audioBusy = false
    private var nextCandidate: GuidedNarrationDraft?
    private(set) var remainingChapterScenes: [GuidedNarrationDraft]?
    @Published private(set) var pendingEndingSessionID: UUID?
    private var deferredAudioChoice: (draft: GuidedNarrationDraft, manual: Bool)?
    private var confirmedPauseTime: TimeInterval?
    private var timedSpeechToken: UUID?
    private var firstWordAfterPauseMilliseconds: Double?

    func chapterPauseConfirmed() {
        confirmedPauseTime = ProcessInfo.processInfo.systemUptime
        firstWordAfterPauseMilliseconds = nil
    }

    func heardFirstWord(_ token: UUID) {
        guard token == timedSpeechToken, let confirmedPauseTime else { return }
        firstWordAfterPauseMilliseconds = (ProcessInfo.processInfo.systemUptime - confirmedPauseTime) * 1000
        self.confirmedPauseTime = nil
        timedSpeechToken = nil
        publish()
    }

    var recordManualAudio: ((GuidedAudioDecision) async throws -> Void)?
    var cancelManualRecording: () -> Void = {}
    private var manualTask: Task<Void, Never>?
    var onChapterSceneSelected: (String) -> Void = { _ in }
    var onAudioApproved: ((GuidedAudioDecision) -> Void)?
    var onEnd: () -> Void = {}
    var onInterrupt: () -> Void = {}
    var practiceApprove: () -> Bool = { false }
    var practiceRedo: () -> Bool = { false }
    var practiceSummary: () -> [String: String]? = { nil }
    var selectedAudioVoice: () -> GuidedAudioVoice? = { nil }
    var prepareAudio: (@MainActor (String, String, Bool, @MainActor () -> Bool) async throws -> GuidedPreparedAudio)?
    var previewAudio: @MainActor (GuidedPreparedAudio, @MainActor () -> Bool) async throws -> Void = { _, _ in }
    var approveAudioVersion: (UUID, String, String) throws -> Void = { _, _, _ in }
    var stopAudioPreview: (UUID?) -> Void = { _ in }
    var canSpeak: @MainActor () async -> String? = { "Guided speech is not connected." }
    var speak: (String, UUID) -> Void = { _, _ in }
    var stopSpeech: () -> Void = {}

    let directory: URL
    private let inbox = GuidedCommandInbox()
    private var scanRequested = false
    private var timer: Timer?
    private var processing = false
    private var checkingSpeech = false
    private var speechToken: UUID?
    private var speechWaiter: CheckedContinuation<Bool, Never>?
    private var audioTask: Task<Void, Never>?
    private var audioOperationID: UUID?
    private var running = false
    private var generation = UUID()

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder
    }
    static func decoder() -> JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder }

    init(directory: URL = GuidedNarrationReview.directory) {
        self.directory = directory
        do {
            try prepareDirectories()
            if let data = try? Data(contentsOf: directory.appendingPathComponent("status.json")),
               let saved = try? Self.decoder().decode(GuidedNarrationSnapshot.self, from: data), saved.schemaVersion == 1 {
                draft = saved.draft; active = saved.active
                remainingChapterScenes = saved.remainingChapterScenes
                nextCandidate = saved.nextCandidate
                pendingEndingSessionID = saved.pendingEndingSessionID
                audioReview = saved.audioReview
                if let draft, active {
                    let latestEvent = FileManager.default.fileExists(atPath: voiceImprovementURL(draft).path) ? voiceImprovementURL(draft) : eventURL(draft)
                    decision = try? Self.decoder().decode(GuidedNarrationDecision.self, from: Data(contentsOf: latestEvent))
                    if decision?.kind == "improveNarration", let voice = audioReview?.voice {
                        audioReview = GuidedAudioReview(voice: voice, attempt: 0)
                    }
                    acknowledged = decision.map { FileManager.default.fileExists(atPath: acknowledgmentURL($0.id).path) } ?? false
                    phase = decision.map { $0.kind == "approveNarration" ? "approved" : "improving" } ?? "suspended"
                    message = decision == nil ? "Review restored. Replay the narration to resume; no speech starts automatically." : "Saved decision restored. Waiting for the agent."
                    if decision?.kind == "approveNarration" {
                        if let data = try? Data(contentsOf: audioEventURL(draft)),
                           let event = try? Self.decoder().decode(GuidedAudioDecision.self, from: data), event.draft == draft, event.schemaVersion == 1, event.kind == "approveAudio", event.audio.versionID != nil {
                            audioDecision = event; audioReview = event.audio
                            audioAcknowledged = FileManager.default.fileExists(atPath: acknowledgmentURL(event.id).path)
                            if saved.phase.hasPrefix("manual") {
                                phase = "manualRetry"; message = "Manual take interrupted. Check FocuSee and press M to record this scene again."
                            } else {
                                phase = "audioApproved"; message = "Approved audio restored. No generation or playback starts automatically."
                            }
                        } else if audioReview != nil {
                            phase = "audioSuspended"; message = "Audio review restored. Replay the saved candidate, or use redo to generate another version."
                        }
                    }
                }
            }
        } catch { message = "Cannot prepare narration review: \(error.localizedDescription)" }
    }

    func start() {
        guard !running else { return }
        running = true
        publish()
        watchInbox()
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.publish()
                self?.watchInbox()
            }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    private func watchInbox() {
        inbox.watch(directory.appendingPathComponent("commands")) { [weak self] in
            Task { @MainActor in
                guard let self, self.running else { return }
                await self.processInbox()
            }
        }
    }

    func stop() {
        running = false; inbox.stop(); timer?.invalidate(); timer = nil
        interruptSpeech()
        publish()
    }

    func speechFinished(_ token: UUID) {
        guard token == speechToken else { return }
        speechToken = nil
        let waiter = speechWaiter; speechWaiter = nil; waiter?.resume(returning: true)
        if active, phase == "reading" {
            phase = "awaitingDecision"
            message = "Approve this wording or request an improvement."
        }
        publish()
    }

    func speechFailed(_ token: UUID) {
        guard token == speechToken else { return }
        speechToken = nil
        let waiter = speechWaiter; speechWaiter = nil; waiter?.resume(returning: false)
        if active, decision == nil { phase = "blocked" }
        message = "Spoken prompt failed. The draft and any saved decision are retained; use Replay Narration when ready."
        publish()
    }

    private func stopOwnedSpeech() {
        speechToken = nil
        let waiter = speechWaiter; speechWaiter = nil; waiter?.resume(returning: false)
        stopSpeech()
    }

    var cancelAudioPreparation: () -> Void = {}

    private func cancelAudio() {
        audioOperationID = nil; audioTask?.cancel(); audioTask = nil; audioBusy = false
        cancelAudioPreparation()
        stopAudioPreview(audioReview?.versionID)
    }

    func interruptSpeech() {
        if manualTask != nil {
            cancelManualTake()
            phase = "manualRetry"; message = "Manual recording interrupted. Press M when ready to retry."
        }
        onInterrupt()
        generation = UUID(); checkingSpeech = false
        let wasAudioReview = decision?.kind == "approveNarration" && audioReview != nil && audioDecision == nil
        cancelAudio(); stopOwnedSpeech()
        if active, wasAudioReview {
            phase = "audioSuspended"; message = "Cloned audio review interrupted. Replay the candidate or use redo when idle."
        } else if active, decision == nil, phase == "reading" || phase == "checking" {
            phase = "suspended"; message = "Narration preview interrupted. Replay it when speech and recording are idle."
        }
        publish()
    }

    /// Guided mode owns A/G in every stage; busy/repeated presses never fall
    /// through to standalone audio actions or approve a later stage.
    @discardableResult func approve() -> Bool {
        if active, phase.hasPrefix("manual") { return true }
        if active, practiceApprove() { return true }
        if active, phase == "audioReady", !audioBusy { approveCurrentAudio() }
        else { choose("approveNarration") }
        return active
    }
    @discardableResult func improve() -> Bool {
        if active, phase.hasPrefix("manual") { return true }
        deferredAudioChoice = nil
        if active, practiceRedo() { return true }
        if active, ["approved", "audioReady", "audioFailed", "audioSuspended"].contains(phase), !audioBusy { generateAudio(forceNewVersion: true) }
        else { choose("improveNarration") }
        return active
    }

    func approveWording() { choose("approveNarration") }

    func startAgentPractice() {
        guard active, phase == "audioReady", !audioBusy else { return }
        approveCurrentAudio()
    }

    var canImproveWording: Bool {
        guard active, audioDecision == nil else { return false }
        if decision == nil { return ["reading", "awaitingDecision"].contains(phase) }
        return decision?.kind == "approveNarration"
    }

    func improveWording() {
        guard canImproveWording else { return }
        choose("improveNarration", fromAudio: decision != nil)
    }

    func startRestoredManualTake(_ approval: GuidedAudioDecision) {
        guard active, approval.id == audioDecision?.id, draft == approval.draft, manualTask == nil else { return }
        startManualTake(approval)
    }

    private func choose(_ kind: String, fromAudio: Bool = false) {
        guard active, let draft else { return }
        let revisingVoice = fromAudio && kind == "improveNarration" && decision?.kind == "approveNarration" && audioDecision == nil
        guard revisingVoice || (decision == nil && ["reading", "awaitingDecision"].contains(phase)) else { return }
        let event = GuidedNarrationDecision(id: UUID(), kind: kind, draft: draft, createdAt: Date())
        do {
            // One immutable event file per revision is authoritative across crashes.
            let url = revisingVoice ? voiceImprovementURL(draft) : eventURL(draft)
            guard !FileManager.default.fileExists(atPath: url.path) else { return }
            try write(event, to: url)
            if revisingVoice {
                deferredAudioChoice = nil
                cancelAudio()
                audioReview = audioReview.map { GuidedAudioReview(voice: $0.voice, attempt: 0) }
            }
            decision = event; acknowledged = false
            phase = kind == "approveNarration" ? "approved" : "improving"
            message = kind == "approveNarration" ? "Narration approved. Waiting for the agent to receive it." : "Improvement requested. Waiting for the agent."
            generation = UUID(); stopOwnedSpeech()
            publish()
            if kind == "approveNarration", prepareAudio != nil {
                generateAudio(forceNewVersion: false)
                return
            }
            let prompt = kind == "approveNarration" ? "Narration approved." : "Improvement requested. Waiting for the agent."
            let epoch = generation
            Task { [weak self] in
                guard let self, self.decision?.id == event.id else { return }
                await self.announce(prompt, expectedGeneration: epoch)
            }
        } catch { message = "Decision was not saved: \(error.localizedDescription). Please retry."; publish() }
    }

    func replay() async {
        guard active, draft != nil, decision == nil, !checkingSpeech else { return }
        checkingSpeech = true
        let expected = generation
        phase = "checking"; publish()
        let issue = await canSpeak()
        guard expected == generation, active, decision == nil else { return }
        checkingSpeech = false
        if let issue { phase = "blocked"; message = issue; publish(); return }
        let token = UUID(); speechToken = token
        phase = "reading"; message = "Reading narration. Approval accepts these exact words; redo requests an improved draft."
        publish()
        if confirmedPauseTime != nil { timedSpeechToken = token }
        speak("Narration ready. \(draft!.narration) Approve or improve.", token)
    }

    private func announce(_ text: String, expectedGeneration: UUID) async {
        guard expectedGeneration == generation, active else { return }
        guard await canSpeak() == nil, expectedGeneration == generation, active else { return }
        let token = UUID(); speechToken = token; publish(); speak(text, token)
    }

    /// Practice uses the same isolated spoken-status route, after any audio
    /// approval confirmation finishes. It does not alter ordinary macOS speech.
    func stopPracticePrompt() {
        generation = UUID(); stopOwnedSpeech()
    }

    func announcePractice(_ text: String) async -> Bool {
        let epoch = generation
        for _ in 0..<200 {
            guard active, generation == epoch, !Task.isCancelled else { return false }
            if speechToken == nil { break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        guard speechToken == nil else { return false }
        do {
            try await sayAndWait(text, isCurrent: { self.active && self.generation == epoch && !Task.isCancelled })
            return true
        } catch { return false }
    }

    func end() {
        cancelManualTake()
        pendingEndingSessionID = nil
        deferredAudioChoice = nil
        confirmedPauseTime = nil
        timedSpeechToken = nil
        nextCandidate = nil
        remainingChapterScenes = nil
        onEnd()
        generation = UUID(); checkingSpeech = false
        cancelAudio(); stopOwnedSpeech()
        active = false; phase = "inactive"; message = "Guided review ended. Standalone audio shortcuts are available."
        publish()
    }

    func generateAudio(forceNewVersion: Bool = false) {
        guard active, let draft, decision?.kind == "approveNarration", audioDecision == nil,
              (!audioBusy || forceNewVersion), let prepareAudio else { return }
        guard let voice = audioReview?.voice ?? selectedAudioVoice() else {
            phase = "audioFailed"; message = "Choose an English cloned voice, then use redo to generate audio. The wording remains approved."
            publish()
            let epoch = generation
            Task { [weak self] in await self?.announce("Narration approved. Choose an English cloned voice, then use redo to generate audio.", expectedGeneration: epoch) }
            return
        }
        generation = UUID(); cancelAudio(); stopOwnedSpeech()
        let epoch = generation, operation = UUID()
        audioOperationID = operation; audioBusy = true
        audioReview = GuidedAudioReview(voice: voice, attempt: (audioReview?.attempt ?? 0) + 1,
                                       versionID: audioReview?.versionID, duration: audioReview?.duration)
        phase = "audioGenerating"; message = "Preparing cloned audio for the approved wording and frozen voice…"; publish()
        audioTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.audioOperationID == operation { self.audioBusy = false; self.audioTask = nil; self.publish() } }
            let isCurrent: @MainActor () -> Bool = { self.active && self.generation == epoch && self.audioOperationID == operation && !Task.isCancelled }
            do {
                try await self.sayAndWait(forceNewVersion ? "Regenerating audio." : "Preparing audio.", cueTimeout: .seconds(3), isCurrent: isCurrent)
                let prepared = try await prepareAudio(draft.narration, voice.id, forceNewVersion, isCurrent)
                guard isCurrent() else { return }
                guard prepared.duration.isFinite, prepared.duration > 0 else { throw self.error("Cloned audio has no playable duration.") }
                self.audioReview?.versionID = prepared.versionID; self.audioReview?.duration = prepared.duration
                self.phase = "audioPreparing"
                self.message = "Voice saved · \(String(format: "%.2f", prepared.duration)) seconds. Preparing preview."
                self.publish()
                try await self.sayAndWait("Review audio.", cueTimeout: .seconds(3), isCurrent: isCurrent)
                try await self.playAudioCandidate(prepared, isCurrent: isCurrent)
            } catch {
                guard isCurrent() else { return }
                self.phase = "audioFailed"
                self.message = "Audio attempt failed. \(error.localizedDescription)"
                self.publish()
            }
        }
    }

    func replayAudio() {
        guard active, decision?.kind == "approveNarration", audioDecision == nil, let audio = audioReview,
              let id = audio.versionID, let duration = audio.duration else { return }
        generation = UUID(); cancelAudio(); stopOwnedSpeech()
        let epoch = generation, operation = UUID()
        audioOperationID = operation; audioBusy = true
        phase = "audioPreparing"; message = "Preparing the saved cloned audio preview…"; publish()
        audioTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.audioOperationID == operation { self.audioBusy = false; self.audioTask = nil; self.publish() } }
            let isCurrent: @MainActor () -> Bool = { self.active && self.generation == epoch && self.audioOperationID == operation && !Task.isCancelled }
            do { try await self.playAudioCandidate(GuidedPreparedAudio(versionID: id, duration: duration), isCurrent: isCurrent) }
            catch {
                guard isCurrent() else { return }
                self.phase = "audioFailed"; self.message = "Audio preview failed: \(error.localizedDescription)"; self.publish()
            }
        }
    }

    private func playAudioCandidate(_ audio: GuidedPreparedAudio, isCurrent: @MainActor () -> Bool) async throws {
        guard isCurrent() else { throw CancellationError() }
        try await previewAudio(audio, isCurrent)
        guard isCurrent() else { return }
        phase = "audioReady"; message = "Listen again, revise the words, regenerate the voice, or choose who will perform the scene."
        publish()
    }

    private func sayAndWait(_ text: String, cueTimeout: Duration? = nil, isCurrent: @escaping @MainActor () -> Bool) async throws {
        if let issue = await canSpeak() { throw error(issue) }
        guard isCurrent() else { throw CancellationError() }
        let token = UUID()
        let watchdog = cueTimeout.map { timeout in
            Task { @MainActor [weak self] in
                try await Task.sleep(for: timeout)
                guard let self, self.speechToken == token, isCurrent() else { return }
                self.stopSpeech()
                self.speechFinished(token)
            }
        }
        defer { watchdog?.cancel() }
        let finished = await withCheckedContinuation { continuation in
            speechToken = token; speechWaiter = continuation
            publish(); speak(text, token)
        }
        try Task.checkCancellation()
        guard finished, isCurrent() else { throw error("Spoken status prompt did not finish.") }
    }

    func beginChapter(_ scenes: [GuidedNarrationDraft]) async throws {
        guard pendingEndingSessionID == nil else { throw error("Waiting for the previous chapter’s final screen to be saved.") }
        guard !active else { throw error("End the active review before starting a chapter.") }
        try await loadChapterScenes(scenes, replacing: false)
    }

    func selectChapterScenes(_ scenes: [GuidedNarrationDraft]) async throws {
        guard active, remainingChapterScenes != nil, draft?.sceneID != scenes.first?.sceneID else { return }
        try await loadChapterScenes(scenes, replacing: true)
    }

    func replaceCurrentSceneWording(_ narration: String) async throws {
        guard active, let draft, var remaining = remainingChapterScenes else { return }
        // Successive saves during a take replace its queued retake.
        if remaining.first?.sceneID == draft.sceneID { remaining.removeFirst() }
        else if let candidate = nextCandidate, remaining.first?.sceneID == candidate.sceneID {
            remaining[0] = candidate
        }
        let replacement = GuidedNarrationDraft(sessionID: UUID(), sceneID: draft.sceneID, revision: 1, narration: narration)
        try await loadChapterScenes([replacement] + remaining, replacing: true)
    }

    private func loadChapterScenes(_ scenes: [GuidedNarrationDraft], replacing: Bool) async throws {
        guard let first = scenes.first,
              scenes.allSatisfy({ !$0.narration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.narration.count <= 12000 }) else {
            throw error("Each remaining scene needs valid narration before review can start.")
        }
        if replacing {
            let practicePhase = practiceSummary()?["phase"] ?? ""
            if phase == "manualRecording" || ["recording", "waitingForRecordActions", "completed"].contains(practicePhase) {
                remainingChapterScenes = scenes
                nextCandidate = nil
                message = "The selected scene will start after this take."
                publish()
                return
            }
            let checkpoint = pendingEndingSessionID
            end()
            pendingEndingSessionID = checkpoint
        }
        remainingChapterScenes = Array(scenes.dropFirst())
        try await readChapterScene(first)
    }

    private func readChapterScene(_ next: GuidedNarrationDraft) async throws {
        try await handle(GuidedNarrationCommand(id: UUID(), sessionID: next.sessionID, kind: "submit", draft: next))
    }

    func guidedTakeFinished(_ approval: GuidedAudioDecision) async {
        guard active, audioDecision?.id == approval.id, draft == approval.draft, remainingChapterScenes != nil else { return }
        do { try await finishTake(endingSessionID: approval.draft.sessionID) }
        catch { message = error.localizedDescription; publish() }
    }

    private func finishTake(endingSessionID: UUID? = nil) async throws {
        let candidate = nextCandidate
        let remaining = remainingChapterScenes
        let pauseTime = confirmedPauseTime
        end()
        confirmedPauseTime = pauseTime
        pendingEndingSessionID = endingSessionID
        if let remaining, let next = remaining.first {
            remainingChapterScenes = Array(remaining.dropFirst())
            try await readChapterScene(candidate ?? next)
        } else if remaining != nil {
            message = "Recording completed for this chapter."
            publish()
            let token = UUID()
            speechToken = token
            timedSpeechToken = token
            speak(message, token)
        }
    }

    private func cancelManualTake() {
        guard let task = manualTask else { return }
        manualTask = nil
        task.cancel()
        cancelManualRecording()
    }

    func recordMyself() {
        guard active, !audioBusy, manualTask == nil, recordManualAudio != nil else { return }
        if phase == "manualRetry", let audioDecision { startManualTake(audioDecision) }
        else if phase == "audioReady" { approveCurrentAudio(manual: true) }
    }

    private func startManualTake(_ approval: GuidedAudioDecision) {
        guard let recordManualAudio else { return }
        phase = "manualRecording"; message = "Recording your screen actions with the approved voice."
        publish()
        manualTask = Task {
            do {
                try Task.checkCancellation()
                try await recordManualAudio(approval)
                try Task.checkCancellation()
                guard active, audioDecision?.id == approval.id else { return }
                manualTask = nil
                try await finishTake()
            } catch {
                guard !Task.isCancelled, active, audioDecision?.id == approval.id else { return }
                manualTask = nil
                phase = "manualRetry"; message = "Manual take did not finish: \(error.localizedDescription) Press M to retry."
                publish()
            }
        }
    }

    private func approveCurrentAudio(manual: Bool = false) {
        guard let draft, let audio = audioReview, let id = audio.versionID else { return }
        if pendingEndingSessionID != nil {
            deferredAudioChoice = (draft, manual)
            message = "Waiting for the previous scene’s ending screen to be saved."
            publish()
            return
        }
        do {
            try approveAudioVersion(id, draft.narration, audio.voice.id)
            let event: GuidedAudioDecision
            if FileManager.default.fileExists(atPath: audioEventURL(draft).path) {
                event = try Self.decoder().decode(GuidedAudioDecision.self, from: Data(contentsOf: audioEventURL(draft)))
                guard event.draft == draft, event.audio.versionID == id, event.audio.voice == audio.voice,
                      event.schemaVersion == 1, event.kind == "approveAudio" else { throw error("A different final audio decision already exists for this narration revision.") }
            } else {
                event = GuidedAudioDecision(id: UUID(), draft: draft, audio: audio, createdAt: Date())
                try write(event, to: audioEventURL(draft))
            }
            audioDecision = event; audioAcknowledged = false
            stopAudioPreview(id)
            phase = "audioApproved"; message = "Exact cloned audio approved. Word timings are saved in the background; recording is not started."
            publish()
            if manual { startManualTake(event); return }
            if let onAudioApproved { onAudioApproved(event); return }
            let epoch = generation
            Task { [weak self] in
                guard let self, self.audioDecision?.id == event.id else { return }
                await self.announce("Cloned audio approved.", expectedGeneration: epoch)
            }
        } catch {
            message = "Could not finish audio approval: \(error.localizedDescription) Replay the candidate or press approve to retry."
            publish()
        }
    }

    func processInbox() async {
        scanRequested = true
        guard !processing else { return }
        processing = true
        defer { processing = false }
        repeat {
            scanRequested = false
            await drainPendingCommands()
        } while scanRequested
    }

    private func drainPendingCommands() async {
        let files = GuidedCommandInbox.pendingFiles(in: directory)
            .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for file in files {
            guard UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil else { continue }
            let receipt = directory.appendingPathComponent("receipts/\(file.lastPathComponent)")
            guard !FileManager.default.fileExists(atPath: receipt.path) else { continue }
            do {
                let command = try Self.decoder().decode(GuidedNarrationCommand.self, from: Data(contentsOf: file))
                guard command.schemaVersion == 1, file.deletingPathExtension().lastPathComponent.lowercased() == command.id.uuidString.lowercased() else { throw error("Invalid command identity or schema.") }
                guard Date().timeIntervalSince(command.createdAt) <= 120,
                      Date().timeIntervalSince(command.createdAt) >= -5 else { throw error("Command expired. Submit a fresh command after checking the current review.") }
                try await handle(command)
                try writeReceipt(commandID: command.id.uuidString, accepted: true, message: message, to: receipt)
            } catch {
                try? writeReceipt(commandID: file.deletingPathExtension().lastPathComponent, accepted: false, message: error.localizedDescription, to: receipt)
            }
        }
    }

    private func handle(_ command: GuidedNarrationCommand) async throws {
        switch command.kind {
        case "submit":
            guard let next = command.draft, next.sessionID == command.sessionID,
                  !next.sceneID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, next.sceneID.count <= 200,
                  next.revision > 0, next.revision <= 100000,
                  !next.narration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, next.narration.count <= 12000 else { throw error("Invalid narration draft.") }
            if active {
                guard let previous = draft, previous.sessionID == next.sessionID, previous.sceneID == next.sceneID else { throw error("Another narration review is active. End it before starting a new session.") }
                if previous == next { return } // Retry never repeats speech or changes a decision.
                guard let decision, decision.kind == "improveNarration", command.eventID == decision.id,
                      next.revision == previous.revision + 1 else { throw error("A revision must answer the current improvement event and increment the revision once.") }
            } else {
                guard next.revision == 1, !FileManager.default.fileExists(atPath: eventURL(next).path) else { throw error("Start a new review with a fresh session ID and revision 1.") }
            }
            if let candidate = command.nextCandidate {
                guard active, let queued = remainingChapterScenes?.first,
                      queued.sessionID == candidate.sessionID, queued.sceneID == candidate.sceneID,
                      queued.revision == candidate.revision, candidate.revision == 1,
                      !candidate.narration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      candidate.narration.count <= 12000 else { throw error("Proposed wording must match the next queued scene.") }
            }
            nextCandidate = command.nextCandidate
            generation = UUID(); cancelAudio(); stopOwnedSpeech()
            let revisedVoice = active && draft?.sessionID == next.sessionID ? audioReview?.voice : nil
            audioReview = revisedVoice.map { GuidedAudioReview(voice: $0, attempt: 0) }
            audioDecision = nil; audioAcknowledged = false
            let enteringChapterScene = remainingChapterScenes != nil && draft?.sessionID != next.sessionID
            draft = next; active = true; decision = nil; acknowledged = false; checkingSpeech = false
            if enteringChapterScene { onChapterSceneSelected(next.sceneID) }
            phase = "ready"; message = "Narration received. Preparing the spoken review."; publish()
            await replay()
        case "acknowledge":
            if active, let event = audioDecision, event.draft.sessionID == command.sessionID, event.id == command.eventID {
                if !audioAcknowledged {
                    try writeReceipt(commandID: command.id.uuidString, accepted: true, message: "Audio approval received by the agent.", to: acknowledgmentURL(event.id))
                    audioAcknowledged = true; publish()
                }
                return
            }
            guard active, let decision, decision.draft.sessionID == command.sessionID, decision.id == command.eventID else { throw error("Acknowledgment does not match the current decision.") }
            if acknowledged { return }
            try writeReceipt(commandID: command.id.uuidString, accepted: true, message: "Decision received by the agent.", to: acknowledgmentURL(decision.id))
            acknowledged = true
            if decision.kind == "improveNarration" { message = "Agent received the improvement request. Waiting for revised narration." }
            else if phase == "approved" { message = "Narration approved and received by the agent." }
            publish()
            // Do not interrupt the decision confirmation with another spoken prompt.
        case "replay":
            guard active, draft?.sessionID == command.sessionID else { throw error("Session does not match the active review.") }
            if decision?.kind == "approveNarration", audioReview?.versionID != nil { replayAudio() }
            else {
                guard decision == nil else { throw error("There is no candidate waiting for review.") }
                await replay()
            }
        case "generateAudio":
            guard active, draft?.sessionID == command.sessionID, decision?.kind == "approveNarration", prepareAudio != nil else { throw error("Approve wording before generating cloned audio.") }
            generateAudio()
        case "chapterTakeCompleted":
            guard pendingEndingSessionID == command.sessionID else { throw error("Ending checkpoint does not match the completed scene.") }
            pendingEndingSessionID = nil
            let choice = deferredAudioChoice
            deferredAudioChoice = nil
            if let choice, active, phase == "audioReady", choice.draft == draft, !audioBusy {
                approveCurrentAudio(manual: choice.manual)
            }
            publish()
        case "end":
            guard draft?.sessionID == command.sessionID else { throw error("Session does not match the current review.") }
            end()
        default: throw error("Unknown narration review command.")
        }
    }

    private func voiceImprovementURL(_ draft: GuidedNarrationDraft) -> URL {
        eventURL(draft).deletingPathExtension().appendingPathExtension("improve.json")
    }
    private func eventURL(_ draft: GuidedNarrationDraft) -> URL {
        directory.appendingPathComponent("events/\(draft.sessionID.uuidString.lowercased())-r\(draft.revision).json")
    }
    private func audioEventURL(_ draft: GuidedNarrationDraft) -> URL {
        directory.appendingPathComponent("audio-events/\(draft.sessionID.uuidString.lowercased())-r\(draft.revision).json")
    }
    private func acknowledgmentURL(_ id: UUID) -> URL { directory.appendingPathComponent("acknowledgments/\(id.uuidString.lowercased()).json") }
    private func prepareDirectories() throws {
        for name in ["", "commands", "receipts", "events", "audio-events", "acknowledgments"] {
            let url = directory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
    }
    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try Self.encoder().encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func writeReceipt(commandID: String, accepted: Bool, message: String, to url: URL) throws {
        struct Receipt: Encodable { var schemaVersion = 1; var commandID: String; var accepted: Bool; var message: String; var updatedAt: Date }
        try write(Receipt(commandID: commandID, accepted: accepted, message: message, updatedAt: Date()), to: url)
    }
    private func publish() {
        do {
            try write(GuidedNarrationSnapshot(appRunning: running, pid: ProcessInfo.processInfo.processIdentifier, updatedAt: Date(), active: active, phase: phase, message: message, draft: draft, decision: decision, acknowledged: acknowledged, speechActive: speechToken != nil, audioReview: audioReview, audioDecision: audioDecision, audioAcknowledged: audioAcknowledged, audioBusy: audioBusy, pendingEndingSessionID: pendingEndingSessionID, firstWordAfterPauseMilliseconds: firstWordAfterPauseMilliseconds, nextCandidate: nextCandidate, remainingChapterScenes: remainingChapterScenes, practice: practiceSummary()), to: directory.appendingPathComponent("status.json"))
        } catch { message = "Could not save narration review status: \(error.localizedDescription)" }
    }
    private func error(_ text: String) -> NSError { NSError(domain: "GuidedNarrationReview", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}
