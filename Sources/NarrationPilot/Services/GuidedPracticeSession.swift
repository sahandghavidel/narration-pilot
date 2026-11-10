import Combine
import CryptoKit
import Foundation

struct GuidedPracticeWord: Codable, Equatable, Sendable {
    var word: String
    var start: Double
    var end: Double
}

struct GuidedPracticeContext: Codable, Equatable, Sendable {
    var draft: GuidedNarrationDraft
    var audioApprovalID: UUID
    var audioVersionID: UUID
    var audioSHA256: String
    var duration: Double
    var audioPath: String
    var transcriptionPath: String
    var words: [GuidedPracticeWord]
}

struct GuidedPracticeAssets: Sendable {
    var context: GuidedPracticeContext
    var audio: Data
}

struct GuidedPracticeAction: Codable, Equatable, Sendable {
    var id: String
    var description: String
    var wordIndex: Int?
    var atSeconds: Double?
}

struct GuidedPracticePlan: Codable, Equatable, Sendable {
    var id: UUID
    var audioVersionID: UUID
    var audioSHA256: String
    var checkpointID: UUID
    var actions: [GuidedPracticeAction]
}

struct GuidedPracticeGate: Codable, Sendable {
    var checkpointID: UUID
    var verifiedAt: Date
    var matched: Bool
    var evidencePath: String
}

struct GuidedPracticeActionResult: Codable, Sendable {
    var actionID: String
    var startedAtSeconds: Double
    var completedAtSeconds: Double
    var succeeded: Bool
    var captureState: String?
}

struct GuidedPracticeEvent: Codable, Sendable {
    var schemaVersion = 1
    var id: UUID
    var kind: String
    var sessionID: UUID
    var runID: UUID
    var attempt: Int
    var audioVersionID: UUID
    var contextPath: String
    var planID: UUID?
    var checkpointID: UUID?
    var createdAt: Date
}

struct GuidedPracticeCommand: Codable, Sendable {
    var schemaVersion = 1
    var id: UUID
    var createdAt = Date()
    var sessionID: UUID
    var runID: UUID
    var kind: String
    var eventID: UUID?
    var plan: GuidedPracticePlan?
    var gate: GuidedPracticeGate?
    var results: [GuidedPracticeActionResult]?
}

struct GuidedPracticeRecordingResult: Codable, Sendable {
    var sessionID: UUID
    var duration: Double
    var message: String
}

struct GuidedPracticeSnapshot: Codable {
    var schemaVersion = 1
    var appRunning: Bool
    var pid: Int32
    var updatedAt: Date
    var active: Bool
    var phase: String
    var message: String
    var approval: GuidedAudioDecision?
    var runID: UUID?
    var attempt: Int
    var contextPath: String?
    var baselineCheckpointID: UUID?
    var plan: GuidedPracticePlan?
    var pendingEvent: GuidedPracticeEvent?
    var eventAcknowledged: Bool
    var promptBusy: Bool
    var elapsed: Double
    var duration: Double
    var currentWordIndex: Int?
    var clockSource: String
    var audioFinished: Bool
    var actionsFinished: Bool
    var actionResults: [GuidedPracticeActionResult]
    var recordingResult: GuidedPracticeRecordingResult?
    var recordingSessionID: UUID?
    var recordActionsFinished: Bool
    var recordActionResults: [GuidedPracticeActionResult]
}

/// The app owns the exact WAV clock and approval gates. The active agent owns
/// real cursor actions and continuity restoration, using the frozen context and
/// a word-anchored plan. No arbitrary action scripts execute inside the app.
@MainActor
final class GuidedPracticeSession: ObservableObject {
    nonisolated static let directory = GuidedNarrationReview.directory.appendingPathComponent("Practice")
    @Published private(set) var active = false
    @Published private(set) var phase = "inactive" { didSet { updateClockTimer() } }
    @Published private(set) var message = "No guided practice is active."
    @Published private(set) var approval: GuidedAudioDecision?
    @Published private(set) var runID: UUID?
    @Published private(set) var attempt = 0
    @Published private(set) var plan: GuidedPracticePlan?
    @Published private(set) var pendingEvent: GuidedPracticeEvent?
    @Published private(set) var eventAcknowledged = false
    @Published private(set) var promptBusy = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var audioFinished = false
    @Published private(set) var actionsFinished = false
    @Published private(set) var recordingResult: GuidedPracticeRecordingResult?
    var currentWordIndex: Int? { assets?.context.words.lastIndex(where: { $0.start <= elapsed && elapsed <= $0.end }) }
    var loadAssets: @MainActor (GuidedAudioDecision) async throws -> GuidedPracticeAssets = { _ in throw CancellationError() }
    var canPractice: @MainActor () async -> String? = { "Practice is not connected." }
    var prompt: @MainActor (String) async -> Bool = { _ in true }
    var recordAudio: @MainActor (GuidedPracticeAssets) async throws -> GuidedPracticeRecordingResult = { _ in throw CancellationError() }
    var chapterCompletion: (GuidedAudioDecision) -> Bool = { _ in false }
    var stopPrompt: () -> Void = {}
    var cancelRecording: (Bool) -> Void = { _ in }
    var recordingProgress: () -> (elapsed: Double, duration: Double, clock: String, sessionID: UUID?) = { (0, 0, "notRecording", nil) }
    var makePlayer: (Data) throws -> any ApprovedAudioPlaying = { try ApprovedWAVPlayer(audio: $0) }

    let directory: URL
    private var assets: GuidedPracticeAssets?
    private var baselineCheckpointID: UUID?
    private var actionResults: [GuidedPracticeActionResult] = []
    private var player: (any ApprovedAudioPlaying)?
    private var recordingSessionID: UUID?
    private var recordActionsFinished = false
    private var recordActionResults: [GuidedPracticeActionResult] = []
    private var audioEndedAt: Double?
    private let inbox = GuidedCommandInbox()
    private var scanRequested = false
    private var timer: Timer?
    private var worker: Task<Void, Never>?
    private var operationID: UUID?
    private var processing = false
    private var running = false
    private var clockSource = "notPrepared"
    private var contextPath: String? { assets.map { contextURL($0.context.audioVersionID).path } }

    init(directory: URL = GuidedPracticeSession.directory) {
        self.directory = directory
        do {
            for name in ["", "commands", "receipts", "events", "acknowledgments", "contexts"] {
                let url = directory.appendingPathComponent(name)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            }
            if let data = try? Data(contentsOf: directory.appendingPathComponent("status.json")),
               let saved = try? GuidedNarrationReview.decoder().decode(GuidedPracticeSnapshot.self, from: data), saved.active {
                active = true; approval = saved.approval; runID = saved.runID; attempt = saved.attempt
                baselineCheckpointID = saved.baselineCheckpointID
                phase = "suspended"; message = "Practice restored. Use redo to reload the approved audio and request a fresh practice. No playback or recording starts automatically."
            }
        } catch { message = "Cannot prepare practice: \(error.localizedDescription)" }
    }

    func start() {
        guard !running else { return }
        running = true
        publish()
        watchInbox()
        updateClockTimer()
    }

    private func updateClockTimer() {
        guard running else { return }
        let interval: TimeInterval = ["practicing", "waitingForActions", "recording"].contains(phase) ? 0.1 : 1
        guard timer?.timeInterval != interval else { return }
        timer?.invalidate()
        timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
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

    func stop() { running = false; inbox.stop(); timer?.invalidate(); timer = nil; suspend(pauseRecording: true) }

    func begin(_ decision: GuidedAudioDecision) {
        cancelWork(pauseRecording: true)
        if approval?.id != decision.id { assets = nil; baselineCheckpointID = nil; attempt = 0 }
        approval = decision; active = true; recordingResult = nil
        requestPractice()
    }

    @discardableResult func approve() -> Bool {
        guard active else { return false }
        guard phase == "practiceReady", audioFinished, actionsFinished else { return true }
        stopPrompt()
        do {
            try emit("recordRequested")
            phase = "recordRequested"; message = "Practice approved. Waiting for the agent to restore the starting checkpoint before recording."
            notify("Preparing recording.")
        } catch { block(error.localizedDescription) }
        return true
    }

    @discardableResult func redo() -> Bool {
        guard active else { return false }
        guard ["practiceReady", "practicing", "waitingForActions", "waitingForRecordActions", "recordRequested", "blocked", "suspended"].contains(phase) else { return true }
        requestPractice()
        return true
    }

    func requestManualRestore() {
        guard active, phase == "practiceReady", audioFinished, actionsFinished else { return }
        stopPrompt()
        do {
            try emit("manualRestoreRequested")
            phase = "manualRestoreRequested"
            message = "Waiting for the agent to restore the starting screen for your take."
            promptBusy = false
            publish()
        } catch { block(error.localizedDescription) }
    }

    func replayPractice() {
        guard active, phase == "practiceReady", plan != nil, assets != nil else { return }
        cancelWork(pauseRecording: false)
        runID = UUID()
        attempt += 1
        audioFinished = false
        actionsFinished = false
        elapsed = 0
        audioEndedAt = nil
        actionResults = []
        do {
            try emit("practiceReplayRequested")
            phase = "practiceRequested"
            message = "Restoring the starting screen to replay the same rehearsal."
            publish()
        } catch { block(error.localizedDescription) }
    }

    func end() {
        cancelWork(pauseRecording: true)
        active = false; phase = "inactive"; message = "Guided practice ended."
        publish()
    }

    func suspend(pauseRecording: Bool = false) {
        guard active else { publish(); return }
        cancelWork(pauseRecording: pauseRecording)
        phase = "suspended"; message = "Practice interrupted. Redo is required before recording."
        pendingEvent = nil; publish()
    }

    private func cancelWork(pauseRecording: Bool) {
        operationID = nil; worker?.cancel(); worker = nil; promptBusy = false
        stopPrompt()
        player?.stop(); player?.completion = nil; player = nil
        if phase == "recording" { cancelRecording(pauseRecording) }
    }

    private func requestPractice() {
        guard let approval else { return }
        cancelWork(pauseRecording: true)
        runID = UUID(); attempt += 1; plan = nil; pendingEvent = nil; eventAcknowledged = false
        audioFinished = false; actionsFinished = false; actionResults = []; audioEndedAt = nil
        recordingResult = nil; recordingSessionID = nil; recordActionsFinished = false; recordActionResults = []
        elapsed = 0; duration = assets?.context.duration ?? approval.audio.duration ?? 0
        phase = "loadingTimings"; message = "Loading the approved WAV and its saved word timings…"; promptBusy = false
        let operation = UUID(); operationID = operation; publish()
        worker = Task { [weak self] in
            guard let self, self.operationID == operation, self.active, !Task.isCancelled else { return }
            do {
                let assets: GuidedPracticeAssets
                if let cached = self.assets { assets = cached } else { assets = try await self.loadAssets(approval) }
                guard self.operationID == operation, self.active, !Task.isCancelled else { return }
                try self.validate(assets, approval: approval)
                self.assets = assets
                self.duration = assets.context.duration
                try self.write(assets.context, to: self.contextURL(assets.context.audioVersionID))
                try self.emit("practiceRequested")
                self.phase = "practiceRequested"; self.message = "Waiting for the agent to plan actions from the word timings and restore the starting screen."
                self.worker = nil; self.publish()
            } catch {
                guard self.operationID == operation, self.active else { return }
                self.block("Practice is not ready: \(error.localizedDescription)")
                self.notify("Practice is not ready. Use redo to retry after checking the review panel.")
            }
        }
    }

    private func validate(_ assets: GuidedPracticeAssets, approval: GuidedAudioDecision) throws {
        let context = assets.context
        let fingerprint = SHA256.hash(data: assets.audio).map { String(format: "%02x", $0) }.joined()
        guard context.draft == approval.draft, context.audioApprovalID == approval.id,
              context.audioVersionID == approval.audio.versionID, context.audioSHA256 == fingerprint,
              context.duration.isFinite, context.duration > 0, !context.words.isEmpty else { throw error("Practice material does not match the exact approved audio.") }
        var previous: Double = 0
        for word in context.words {
            guard !word.word.isEmpty, word.start.isFinite, word.end.isFinite,
                  word.start >= previous, word.end >= word.start, word.end <= context.duration + 0.5 else { throw error("Saved word timings are invalid for this WAV.") }
            previous = word.start
        }
    }

    private func validateGate(_ gate: GuidedPracticeGate?, checkpoint: UUID) throws {
        guard let gate, gate.checkpointID == checkpoint, gate.matched,
              Date().timeIntervalSince(gate.verifiedAt) >= -5, Date().timeIntervalSince(gate.verifiedAt) <= 30,
              gate.evidencePath.hasPrefix("/"), FileManager.default.fileExists(atPath: gate.evidencePath) else {
            throw error("A fresh, matched starting-screen/cursor continuity gate with saved evidence is required.")
        }
    }

    private func beginPlayback(gate: GuidedPracticeGate?) async throws {
        guard phase == "practiceRequested", !promptBusy, let plan, let assets else { throw error("Submit the action plan before starting practice.") }
        try validateGate(gate, checkpoint: plan.checkpointID)
        let operation = UUID(), expectedRun = runID
        operationID = operation; phase = "preparingPractice"; promptBusy = true; publish()
        let prepared: any ApprovedAudioPlaying
        do { prepared = try makePlayer(assets.audio) }
        catch { promptBusy = false; block(error.localizedDescription); throw error }
        guard abs(prepared.duration - assets.context.duration) <= 0.02 else { prepared.stop(); block("WAV duration changed. Reload practice material."); throw error(message) }
        let issue = await canPractice()
        guard operationID == operation, runID == expectedRun, active else { prepared.stop(); throw CancellationError() }
        if let issue { prepared.stop(); promptBusy = false; block(issue); throw error(issue) }
        guard operationID == operation, runID == expectedRun, active else { prepared.stop(); throw CancellationError() }
        guard await prompt("Practice."), operationID == operation, runID == expectedRun, active else {
            prepared.stop()
            if operationID == operation, active { promptBusy = false; block("Practice prompt interrupted.") }
            throw CancellationError()
        }
        let latestIssue = await canPractice()
        guard operationID == operation, runID == expectedRun, active else { prepared.stop(); throw CancellationError() }
        if let latestIssue { prepared.stop(); promptBusy = false; block(latestIssue); throw error(latestIssue) }
        promptBusy = false
        player = prepared; clockSource = prepared.clockSource
        prepared.completion = { [weak self] success in
            guard let self, self.operationID == operation, self.runID == expectedRun else { return }
            self.player?.stop(); self.player?.completion = nil; self.player = nil
            if !success { self.block("Practice audio did not finish. Use redo."); return }
            self.elapsed = self.duration; self.audioFinished = true
            self.audioEndedAt = ProcessInfo.processInfo.systemUptime
            self.phase = "waitingForActions"; self.message = "Audio finished. Waiting for the agent's action results."
            self.finishIfReady(); self.publish()
        }
        phase = "practicing"; message = "Playing the approved WAV. Agent actions follow the saved word timings; FocuSee stays paused."
        guard prepared.play() else { player?.stop(); player = nil; block("Practice audio could not start."); throw error(message) }
        publish()
    }

    private func finishIfReady() {
        guard audioFinished, actionsFinished, ["practicing", "waitingForActions"].contains(phase) else { return }
        phase = "practiceReady"; message = "Practice finished. Approve to restore the start and record; request an improvement to rehearse revised actions with this same audio."
        notify("Practice finished. Choose replay, improve, agent recording, or record myself.")
    }

    private func beginRecording(gate: GuidedPracticeGate?) throws {
        guard phase == "recordRequested", !promptBusy, let plan, let assets else { throw error("Practice approval and a finished preparation prompt are required before recording.") }
        try validateGate(gate, checkpoint: plan.checkpointID)
        let operation = UUID(); operationID = operation
        phase = "recording"; message = "Recording the approved practice plan with the same frozen WAV…"; publish()
        worker = Task { [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                let result = try await self.recordAudio(assets)
                guard self.operationID == operation, self.active else { return }
                self.recordingResult = result; self.recordingSessionID = result.sessionID
                self.elapsed = result.duration; self.duration = result.duration
                self.phase = "waitingForRecordActions"; self.message = "Audio recording finished. Waiting for the agent's action results."
                self.worker = nil; self.completeRecordingIfReady(); self.publish()
            } catch {
                guard self.operationID == operation, self.active else { return }
                self.block("Recording did not finish: \(error.localizedDescription)")
            }
        }
    }

    private func completeRecordingIfReady() {
        guard phase != "completed", recordActionsFinished, let recordingResult else { return }
        do {
            phase = "completed"; message = recordingResult.message
            try emit("recordingCompleted")
            publish()
            if let approval, chapterCompletion(approval) { return }
            notify("Scene recording finished.")
        } catch { block(error.localizedDescription) }
    }

    private func validatedResults(_ results: [GuidedPracticeActionResult]?, recording: Bool) throws -> [GuidedPracticeActionResult] {
        guard let plan, let results, Set(results.map(\.actionID)) == Set(plan.actions.map(\.id)), results.count == plan.actions.count else {
            throw error("Report each planned action exactly once after performing it.")
        }
        for result in results {
            guard result.succeeded, result.startedAtSeconds.isFinite, result.completedAtSeconds.isFinite,
                  result.startedAtSeconds >= 0, result.completedAtSeconds >= result.startedAtSeconds,
                  !recording || result.captureState == "recording" else {
                throw error("Failed actions or actions outside observed recording cannot finish this take.")
            }
        }
        return results
    }

    private func notify(_ text: String) {
        promptBusy = true; let expectedRun = runID, expectedPhase = phase
        publish()
        Task { [weak self] in
            guard let self, self.runID == expectedRun, self.phase == expectedPhase, self.active else { return }
            _ = await self.prompt(text)
            guard self.runID == expectedRun, self.phase == expectedPhase, self.active else { return }
            self.promptBusy = false; self.publish()
        }
    }

    private func emit(_ kind: String) throws {
        guard let approval, let runID, let id = approval.audio.versionID, let contextPath else { throw error("Practice context is unavailable.") }
        let event = GuidedPracticeEvent(id: UUID(), kind: kind, sessionID: approval.draft.sessionID, runID: runID,
            attempt: attempt, audioVersionID: id, contextPath: contextPath, planID: plan?.id,
            checkpointID: baselineCheckpointID, createdAt: Date())
        try write(event, to: directory.appendingPathComponent("events/\(event.id.uuidString.lowercased()).json"))
        pendingEvent = event; eventAcknowledged = false
    }

    private func tick() {
        if phase == "practicing", let player { elapsed = min(duration, max(0, player.currentTime)) }
        if phase == "waitingForActions", let audioEndedAt { elapsed = duration + ProcessInfo.processInfo.systemUptime - audioEndedAt; clockSource = "audioEndPlusMonotonic" }
        if phase == "recording" {
            let progress = recordingProgress(); elapsed = progress.elapsed
            if progress.duration > 0 { duration = progress.duration }
            clockSource = progress.clock; recordingSessionID = progress.sessionID
        }
        publish()
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
        tick()
        let files = GuidedCommandInbox.pendingFiles(in: directory)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for file in files {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { continue }
            let receipt = directory.appendingPathComponent("receipts/\(file.lastPathComponent)")
            guard !FileManager.default.fileExists(atPath: receipt.path) else { continue }
            do {
                let command = try GuidedNarrationReview.decoder().decode(GuidedPracticeCommand.self, from: Data(contentsOf: file))
                guard command.schemaVersion == 1, command.id == id, active, command.runID == runID,
                      command.sessionID == approval?.draft.sessionID,
                      Date().timeIntervalSince(command.createdAt) >= -5, Date().timeIntervalSince(command.createdAt) <= 120 else { throw error("Stale or mismatched practice command.") }
                try await handle(command)
                try writeReceipt(id, true, message, to: receipt)
            } catch { try? writeReceipt(id, false, error.localizedDescription, to: receipt) }
        }
    }

    private func handle(_ command: GuidedPracticeCommand) async throws {
        switch command.kind {
        case "acknowledge":
            guard command.eventID == pendingEvent?.id else { throw error("Event does not match the current practice request.") }
            eventAcknowledged = true
            try writeReceipt(command.id, true, "Agent received practice request.", to: directory.appendingPathComponent("acknowledgments/\(command.eventID!.uuidString.lowercased()).json"))
        case "plan":
            guard phase == "practiceRequested", pendingEvent?.kind != "practiceReplayRequested", let submitted = command.plan, let assets,
                  submitted.audioVersionID == assets.context.audioVersionID, submitted.audioSHA256 == assets.context.audioSHA256,
                  baselineCheckpointID == nil || baselineCheckpointID == submitted.checkpointID else { throw error("Plan does not match the audio or original starting checkpoint.") }
            guard Set(submitted.actions.map(\.id)).count == submitted.actions.count else { throw error("Action IDs must be unique.") }
            for action in submitted.actions {
                guard !action.id.isEmpty, !action.description.isEmpty else { throw error("Every action needs an ID and description.") }
                if let index = action.wordIndex {
                    guard assets.context.words.indices.contains(index), assets.context.words[index].start <= duration, action.atSeconds == nil else { throw error("Invalid word anchor.") }
                } else {
                    guard let seconds = action.atSeconds, seconds.isFinite, seconds >= 0, seconds <= duration else { throw error("Action must anchor to a saved word index or a valid audio time.") }
                }
            }
            plan = submitted; baselineCheckpointID = submitted.checkpointID
        case "start": try await beginPlayback(gate: command.gate)
        case "finish":
            guard ["practicing", "waitingForActions"].contains(phase) else { throw error("Practice must be running or waiting for action results.") }
            actionResults = try validatedResults(command.results, recording: false)
            actionsFinished = true; finishIfReady()
        case "manualReady":
            guard phase == "manualRestoreRequested", let plan else { throw error("No manual handoff requested.") }
            try validateGate(command.gate, checkpoint: plan.checkpointID)
            phase = "manualReady"
            message = "Starting screen restored. Choose Record myself to start your take."
            notify("Ready. Press Command Shift M to start your take.")
        case "record": try beginRecording(gate: command.gate)
        case "recordFinish":
            guard ["recording", "waitingForRecordActions"].contains(phase) else { throw error("No recording is waiting for these action results.") }
            recordActionResults = try validatedResults(command.results, recording: true)
            recordActionsFinished = true; completeRecordingIfReady()
        case "abort":
            cancelWork(pauseRecording: true); block("Agent stopped the take because an action failed. Use redo to practice again.")
        default: throw error("Unknown practice command.")
        }
        publish()
    }

    private func block(_ text: String) {
        player?.stop(); player?.completion = nil; player = nil
        phase = "blocked"; message = text; publish()
    }
    private func contextURL(_ id: UUID) -> URL { directory.appendingPathComponent("contexts/\(id.uuidString.lowercased()).json") }
    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try GuidedNarrationReview.encoder().encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func writeReceipt(_ id: UUID, _ accepted: Bool, _ message: String, to url: URL) throws {
        struct Receipt: Codable { var schemaVersion = 1; var commandID: UUID; var accepted: Bool; var message: String }
        try write(Receipt(commandID: id, accepted: accepted, message: message), to: url)
    }
    private func publish() {
        let state = GuidedPracticeSnapshot(appRunning: running, pid: ProcessInfo.processInfo.processIdentifier, updatedAt: Date(),
            active: active, phase: phase, message: message, approval: approval, runID: runID, attempt: attempt,
            contextPath: contextPath, baselineCheckpointID: baselineCheckpointID, plan: plan, pendingEvent: pendingEvent,
            eventAcknowledged: eventAcknowledged, promptBusy: promptBusy, elapsed: elapsed, duration: duration,
            currentWordIndex: currentWordIndex, clockSource: clockSource, audioFinished: audioFinished,
            actionsFinished: actionsFinished, actionResults: actionResults, recordingResult: recordingResult, recordingSessionID: recordingSessionID,
            recordActionsFinished: recordActionsFinished, recordActionResults: recordActionResults)
        try? write(state, to: directory.appendingPathComponent("status.json"))
    }
    private func error(_ text: String) -> NSError { NSError(domain: "GuidedPractice", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}
