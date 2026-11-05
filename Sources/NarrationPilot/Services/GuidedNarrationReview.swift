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
    private var timer: Timer?
    private var processing = false
    private var checkingSpeech = false
    private var speechToken: UUID?
    private var speechWaiter: CheckedContinuation<Bool, Never>?
    private var audioTask: Task<Void, Never>?
    private var audioOperationID: UUID?
    private var running = false
    private var generation = UUID()
    private var lastHeartbeat = Date.distantPast

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
                audioReview = saved.audioReview
                if let draft, active {
                    decision = try? Self.decoder().decode(GuidedNarrationDecision.self, from: Data(contentsOf: eventURL(draft)))
                    acknowledged = decision.map { FileManager.default.fileExists(atPath: acknowledgmentURL($0.id).path) } ?? false
                    phase = decision.map { $0.kind == "approveNarration" ? "approved" : "improving" } ?? "suspended"
                    message = decision == nil ? "Review restored. Replay the narration to resume; no speech starts automatically." : "Saved decision restored. Waiting for the agent."
                    if decision?.kind == "approveNarration" {
                        if let data = try? Data(contentsOf: audioEventURL(draft)),
                           let event = try? Self.decoder().decode(GuidedAudioDecision.self, from: data), event.draft == draft, event.schemaVersion == 1, event.kind == "approveAudio", event.audio.versionID != nil {
                            audioDecision = event; audioReview = event.audio
                            audioAcknowledged = FileManager.default.fileExists(atPath: acknowledgmentURL(event.id).path)
                            phase = "audioApproved"; message = "Approved audio restored. No generation or playback starts automatically."
                        } else if audioReview != nil {
                            phase = "audioSuspended"; message = "Audio review restored. Replay the saved candidate, or use redo to generate another version."
                        }
                    }
                }
            }
        } catch { message = "Cannot prepare narration review: \(error.localizedDescription)" }
    }

    func start() {
        guard timer == nil else { return }
        running = true
        publish()
        timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.processInbox() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func stop() {
        running = false; timer?.invalidate(); timer = nil
        interruptSpeech()
        publish()
    }

    func speechFinished(_ token: UUID) {
        guard token == speechToken else { return }
        speechToken = nil
        let waiter = speechWaiter; speechWaiter = nil; waiter?.resume(returning: true)
        if active, phase == "reading" {
            phase = "awaitingDecision"
            message = "Review narration: use the approval shortcut for wording, or regeneration shortcut to request improvement."
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

    private func cancelAudio() {
        audioOperationID = nil; audioTask?.cancel(); audioTask = nil; audioBusy = false
        stopAudioPreview(audioReview?.versionID)
    }

    func interruptSpeech() {
        onInterrupt()
        generation = UUID(); checkingSpeech = false
        let wasAudioReview = audioReview != nil && audioDecision == nil
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
        if active, practiceApprove() { return true }
        if active, phase == "audioReady", !audioBusy { approveCurrentAudio() }
        else { choose("approveNarration") }
        return active
    }
    @discardableResult func improve() -> Bool {
        if active, practiceRedo() { return true }
        if active, ["approved", "audioReady", "audioFailed", "audioSuspended"].contains(phase), !audioBusy { generateAudio(forceNewVersion: true) }
        else { choose("improveNarration") }
        return active
    }

    private func choose(_ kind: String) {
        guard active, let draft, decision == nil,
              phase == "reading" || phase == "awaitingDecision" else { return }
        let event = GuidedNarrationDecision(id: UUID(), kind: kind, draft: draft, createdAt: Date())
        do {
            // One immutable event file per revision is authoritative across crashes.
            let url = eventURL(draft)
            guard !FileManager.default.fileExists(atPath: url.path) else { return }
            try write(event, to: url)
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
        onEnd()
        generation = UUID(); checkingSpeech = false
        cancelAudio(); stopOwnedSpeech()
        active = false; phase = "inactive"; message = "Guided review ended. Standalone audio shortcuts are available."
        publish()
    }

    func generateAudio(forceNewVersion: Bool = false) {
        guard active, let draft, decision?.kind == "approveNarration", audioDecision == nil,
              !audioBusy, let prepareAudio else { return }
        guard let voice = audioReview?.voice ?? selectedAudioVoice() else {
            phase = "audioFailed"; message = "Choose an English cloned voice, then use redo to generate audio. The wording remains approved."
            publish()
            let epoch = generation
            Task { [weak self] in await self?.announce("Narration approved. Choose an English cloned voice, then use redo to generate audio.", expectedGeneration: epoch) }
            return
        }
        generation = UUID(); stopOwnedSpeech(); stopAudioPreview(audioReview?.versionID)
        let epoch = generation, operation = UUID()
        audioOperationID = operation; audioBusy = true
        audioReview = GuidedAudioReview(voice: voice, attempt: (audioReview?.attempt ?? 0) + 1)
        phase = "audioGenerating"; message = "Preparing cloned audio for the approved wording and frozen voice…"; publish()
        audioTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.audioOperationID == operation { self.audioBusy = false; self.audioTask = nil; self.publish() } }
            let isCurrent: @MainActor () -> Bool = { self.active && self.generation == epoch && self.audioOperationID == operation && !Task.isCancelled }
            do {
                try await self.sayAndWait(forceNewVersion ? "Regenerating audio." : "Preparing audio.", isCurrent: isCurrent)
                let prepared = try await prepareAudio(draft.narration, voice.id, forceNewVersion, isCurrent)
                guard isCurrent() else { return }
                guard prepared.duration.isFinite, prepared.duration > 0 else { throw self.error("Cloned audio has no playable duration.") }
                self.audioReview?.versionID = prepared.versionID; self.audioReview?.duration = prepared.duration
                try await self.playAudioCandidate(prepared, isCurrent: isCurrent)
            } catch {
                guard isCurrent() else { return }
                self.phase = "audioFailed"; self.message = "Cloned audio is not ready: \(error.localizedDescription) The wording and previous audio approvals are retained."
                self.publish()
                try? await self.sayAndWait("Cloned audio is not ready. Check the review panel, then use redo to retry.", isCurrent: isCurrent)
            }
        }
    }

    func replayAudio() {
        guard active, audioDecision == nil, !audioBusy, let audio = audioReview,
              let id = audio.versionID, let duration = audio.duration else { return }
        generation = UUID(); stopOwnedSpeech(); stopAudioPreview(audio.versionID)
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
        try await sayAndWait("Review audio.", isCurrent: isCurrent)
        try await previewAudio(audio, isCurrent)
        guard isCurrent() else { stopAudioPreview(audio.versionID); return }
        phase = "audioReady"; message = "Review cloned audio: approve saves this exact version; redo generates another with the same wording and voice."
        publish()
    }

    private func sayAndWait(_ text: String, isCurrent: @MainActor () -> Bool) async throws {
        if let issue = await canSpeak() { throw error(issue) }
        guard isCurrent() else { throw CancellationError() }
        let finished = await withCheckedContinuation { continuation in
            let token = UUID(); speechToken = token; speechWaiter = continuation
            publish(); speak(text, token)
        }
        try Task.checkCancellation()
        guard finished, isCurrent() else { throw error("Spoken status prompt did not finish.") }
    }

    private func approveCurrentAudio() {
        guard let draft, let audio = audioReview, let id = audio.versionID else { return }
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
        guard !processing else { return }
        processing = true
        defer { processing = false }
        if Date().timeIntervalSince(lastHeartbeat) >= 1 { publish(); lastHeartbeat = Date() }
        let files = ((try? FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("commands"), includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.pathExtension == "json" }
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
            generation = UUID(); cancelAudio(); stopOwnedSpeech()
            audioReview = nil; audioDecision = nil; audioAcknowledged = false
            draft = next; active = true; decision = nil; acknowledged = false; checkingSpeech = false
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
        case "end":
            guard draft?.sessionID == command.sessionID else { throw error("Session does not match the current review.") }
            end()
        default: throw error("Unknown narration review command.")
        }
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
            try write(GuidedNarrationSnapshot(appRunning: running, pid: ProcessInfo.processInfo.processIdentifier, updatedAt: Date(), active: active, phase: phase, message: message, draft: draft, decision: decision, acknowledged: acknowledged, speechActive: speechToken != nil, audioReview: audioReview, audioDecision: audioDecision, audioAcknowledged: audioAcknowledged, audioBusy: audioBusy, practice: practiceSummary()), to: directory.appendingPathComponent("status.json"))
        } catch { message = "Could not save narration review status: \(error.localizedDescription)" }
    }
    private func error(_ text: String) -> NSError { NSError(domain: "GuidedNarrationReview", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}
