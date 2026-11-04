import AVFoundation
import Combine
import Foundation

struct ApprovedAudioRecordingSettings: Codable, Equatable {
    var before: ExternalTriggerAction = .ensureRecording
    var after: ExternalTriggerAction = .ensurePaused
    var delayBefore: Double = 0
    var delayAfter: Double = 0
    var waitsForNeon = false
    var waitsForInputIdle = true

    var normalized: Self {
        var copy = self
        copy.delayBefore = delayBefore.isFinite ? min(10, max(0, delayBefore)) : 0
        copy.delayAfter = delayAfter.isFinite ? min(10, max(0, delayAfter)) : 0
        return copy
    }
}

@MainActor
protocol ApprovedAudioPlaying: AnyObject {
    var duration: TimeInterval { get }
    var currentTime: TimeInterval { get }
    var completion: ((Bool) -> Void)? { get set }
    func play() -> Bool
    func stop()
}

@MainActor
final class ApprovedWAVPlayer: NSObject, ApprovedAudioPlaying, AVAudioPlayerDelegate {
    private let player: AVAudioPlayer
    var completion: ((Bool) -> Void)?
    var duration: TimeInterval { player.duration }
    var currentTime: TimeInterval { player.currentTime }

    init(audio: Data) throws {
        player = try AVAudioPlayer(data: audio)
        super.init()
        player.delegate = self
        guard player.duration.isFinite, player.duration > 0, player.prepareToPlay() else {
            throw NSError(domain: "ApprovedAudioRecording", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The approved WAV cannot be prepared for playback."])
        }
    }
    func play() -> Bool { player.play() }
    func stop() { player.stop() }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.completion?(flag) }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in self?.completion?(false) }
    }
}

/// Reuses the app's verified external actions and wait services, with WAV completion
/// as the trigger for finishing. Does not synthesize speech or advance script scenes.
@MainActor
final class ApprovedAudioRecordingSession: ObservableObject {
    @Published var settings: ApprovedAudioRecordingSettings {
        didSet {
            if let data = try? JSONEncoder().encode(settings.normalized) { defaults.set(data, forKey: Self.settingsKey) }
        }
    }
    @Published private(set) var isBusy = false
    @Published private(set) var phase = "idle"
    @Published private(set) var message = "Copy approved narration, then record its saved audio."
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    var remaining: TimeInterval { max(0, duration - elapsed) }

    var speechIsIdle: () -> Bool = { true }
    var performAction: (ExternalTriggerAction) async -> String? = { _ in "Recording actions are not connected." }
    var recordingState: () async -> FocuSeeRecordingState = {
        await Task.detached(priority: .utility) { FocuSeeAccessibilityService().recordingState() }.value
    }
    var startCue: () async -> Void = {}
    var stopCue: () async -> Void = {}
    var failureCue: () -> Void = {}
    var waitForNeon: () async -> Void = {}
    var waitForInputIdle: () async -> Void = {}
    var makePlayer: (Data) throws -> any ApprovedAudioPlaying = { try ApprovedWAVPlayer(audio: $0) }

    private static let settingsKey = "narrationPilot.approvedAudioRecording.settings"
    nonisolated static let feedbackURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/local.clipboardreadermac/Runtime/approved-audio-recording.json")
    private let defaults: UserDefaults
    private let feedbackURL: URL
    private var task: Task<Void, Never>?
    private var player: (any ApprovedAudioPlaying)?
    private var playbackContinuation: CheckedContinuation<Bool, Never>?
    private var timer: Timer?
    private var pauseOnCancel = true
    private var takeID: UUID?
    private var sessionID: UUID?

    init(defaults: UserDefaults = .standard, feedbackURL: URL = ApprovedAudioRecordingSession.feedbackURL) {
        self.defaults = defaults
        self.feedbackURL = feedbackURL
        settings = defaults.data(forKey: Self.settingsKey)
            .flatMap { try? JSONDecoder().decode(ApprovedAudioRecordingSettings.self, from: $0) }?.normalized ?? .init()
    }

    func report(_ error: String) {
        guard !isBusy else { return }
        sessionID = nil; takeID = nil
        elapsed = 0; duration = 0
        transition("blocked", error)
    }

    @discardableResult
    func start(audio: Data, takeID: UUID) -> Task<Void, Never>? {
        guard !isBusy else { return nil }
        guard speechIsIdle() else { report("Wait for macOS speech and recording actions to finish first."); return nil }
        let prepared: any ApprovedAudioPlaying
        do { prepared = try makePlayer(audio) }
        catch { report(error.localizedDescription); return nil }
        guard prepared.duration.isFinite, prepared.duration > 0 else { report("The approved WAV has no playable duration."); return nil }
        let configuration = settings.normalized
        self.takeID = takeID
        sessionID = UUID()
        player = prepared
        elapsed = 0
        duration = prepared.duration
        isBusy = true
        pauseOnCancel = true
        transition("preparing", "Approved WAV prepared. Starting recording actions…")
        timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateClock() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        task = Task { [weak self] in
            guard let self else { return }
            var mayNeedPause = false
            defer {
                self.player?.stop()
                self.player?.completion = nil
                self.player = nil
                self.timer?.invalidate(); self.timer = nil
                self.isBusy = false
                self.task = nil
                self.publish()
            }
            do {
                try Task.checkCancellation()
                if configuration.before == .ensureRecording { await self.startCue() }
                try Task.checkCancellation()
                guard self.speechIsIdle() else { throw self.error("macOS speech became active before playback.") }
                self.transition("starting", "Running the before-playback action…")
                mayNeedPause = configuration.before == .ensureRecording || configuration.before == .toggle
                if let error = await self.performAction(configuration.before) { throw self.error(error) }
                try Task.checkCancellation()
                if configuration.before != .none, configuration.delayBefore > 0 {
                    self.transition("beforeDelay", "Waiting before WAV playback…")
                    try await Task.sleep(for: .seconds(configuration.delayBefore))
                }
                if configuration.before == .ensureRecording {
                    guard await self.recordingState() == .recording else {
                        throw self.error("FocuSee is no longer confirmed recording. WAV playback cancelled.")
                    }
                }
                try Task.checkCancellation()
                guard self.speechIsIdle() else { throw self.error("macOS speech became active before playback.") }
                self.transition("playing", "Playing the approved WAV at its original speed…")
                if configuration.after == .ensurePaused { mayNeedPause = true }
                let finished = await self.playToCompletion(prepared)
                try Task.checkCancellation()
                guard finished else { throw self.error("Approved audio did not finish playing.") }
                self.elapsed = self.duration
                if configuration.after != .none, configuration.delayAfter > 0 {
                    self.transition("afterDelay", "Audio finished. Waiting before the after-playback action…")
                    try await Task.sleep(for: .seconds(configuration.delayAfter))
                }
                if configuration.after == .ensurePaused && configuration.waitsForNeon {
                    self.transition("waitingForNeon", "Audio finished. Waiting for Neon Spotlight…")
                    await self.waitForNeon()
                }
                try Task.checkCancellation()
                if configuration.after == .ensurePaused && configuration.waitsForInputIdle {
                    self.transition("waitingForInput", "Audio finished. Waiting until mouse and keyboard are idle…")
                    await self.waitForInputIdle()
                }
                try Task.checkCancellation()
                self.transition("finishing", "Running the after-playback action…")
                if let error = await self.performAction(configuration.after) { throw self.error(error) }
                if configuration.after == .ensurePaused { mayNeedPause = false; await self.stopCue() }
                try Task.checkCancellation()
                self.transition("completed", "Approved audio take completed.")
            } catch {
                self.player?.stop()
                let cancelled = Task.isCancelled
                var cleanupError: String?
                if mayNeedPause && (!cancelled || self.pauseOnCancel) {
                    // Cancellation must not prevent the verified pause's own delay/check.
                    let cleanup = Task { await self.performAction(.ensurePaused) }
                    cleanupError = await cleanup.value
                }
                if !cancelled { self.failureCue() }
                self.transition(cancelled ? "cancelled" : "failed",
                    (cancelled ? "Cloned audio take cancelled." : error.localizedDescription)
                    + (cleanupError.map { " Could not confirm pause: \($0)" } ?? ""))
            }
        }
        return task
    }

    func cancel(pauseRecording: Bool = true) {
        guard isBusy else { return }
        pauseOnCancel = pauseRecording
        task?.cancel()
        if phase == "playing", let player { elapsed = min(duration, max(0, player.currentTime)) }
        player?.stop()
        let continuation = playbackContinuation
        playbackContinuation = nil
        continuation?.resume(returning: false)
    }

    private func playToCompletion(_ player: any ApprovedAudioPlaying) async -> Bool {
        let playbackID = sessionID
        return await withCheckedContinuation { continuation in
            playbackContinuation = continuation
            player.completion = { [weak self] finished in
                guard let self, self.sessionID == playbackID else { return }
                let continuation = self.playbackContinuation
                self.playbackContinuation = nil
                continuation?.resume(returning: finished)
            }
            if !player.play(), let pending = playbackContinuation {
                playbackContinuation = nil
                pending.resume(returning: false)
            }
        }
    }

    private func updateClock() {
        if phase == "playing", let player { elapsed = min(duration, max(0, player.currentTime)) }
        publish()
    }

    private func transition(_ phase: String, _ message: String) {
        self.phase = phase
        self.message = message
        publish()
    }

    private func publish() {
        let payload: [String: Any] = ["schemaVersion": 1, "updatedAt": ISO8601DateFormatter().string(from: Date()),
            "pid": ProcessInfo.processInfo.processIdentifier, "sessionID": sessionID?.uuidString ?? "",
            "audioVersionID": takeID?.uuidString ?? "", "phase": phase, "busy": isBusy,
            "staleAfterSeconds": 1, "playbackRate": 1.0,
            "elapsedSeconds": elapsed, "remainingSeconds": remaining, "durationSeconds": duration,
            "clockSource": "AVAudioPlayer.currentTime", "durationIsEstimate": false, "message": message]
        do {
            try FileManager.default.createDirectory(at: feedbackURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]).write(to: feedbackURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: feedbackURL.path)
        } catch { /* Playback and pause must not fail because diagnostics cannot be written. */ }
    }

    private func error(_ message: String) -> NSError {
        NSError(domain: "ApprovedAudioRecording", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
