import Foundation

@MainActor
private final class FakeWAVPlayer: ApprovedAudioPlaying {
    var duration: TimeInterval = 1.25
    var currentTime: TimeInterval = 0
    var completion: ((Bool) -> Void)?
    var didPlay = false
    var didStop = false
    var playSucceeds = true
    var onPlay: () -> Void = {}
    func play() -> Bool { didPlay = true; onPlay(); return playSucceeds }
    func stop() { didStop = true }
}

@main
struct ApprovedAudioRecordingCheck {
    @MainActor static func main() async throws {
        let suite = "NarrationPilot.ApprovedRecordingCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        func session() -> ApprovedAudioRecordingSession {
            ApprovedAudioRecordingSession(defaults: defaults, feedbackURL: folder.appendingPathComponent("status.json"))
        }
        func waitFor(_ predicate: @MainActor () -> Bool) async throws {
            for _ in 0..<100 {
                if predicate() { return }
                try await Task.sleep(for: .milliseconds(10))
            }
            preconditionFailure("Timed out waiting for recording stage")
        }
        let recording = session()
        precondition(recording.settings.before == .ensureRecording && recording.settings.after == .ensurePaused)
        precondition(recording.settings.waitsForInputIdle)
        recording.settings.waitsForNeon = true
        recording.settings.delayBefore = 0.02
        recording.settings.delayAfter = 0.02
        precondition(session().settings == recording.settings)
        var events: [String] = []
        var fake = FakeWAVPlayer()
        recording.makePlayer = { _ in fake }
        recording.performAction = { action in events.append(action.rawValue); return nil }
        recording.recordingState = { events.append("verifyRecording"); return .recording }
        recording.startCue = { events.append("startCue") }
        recording.stopCue = { events.append("stopCue") }
        recording.waitForNeon = { events.append("neon") }
        recording.waitForInputIdle = { events.append("inputIdle") }
        fake.onPlay = { events.append("play") }
        let take = recording.start(audio: Data(), takeID: UUID())!
        precondition(recording.start(audio: Data(), takeID: UUID()) == nil)
        try await waitFor { fake.didPlay }
        fake.currentTime = 0.4
        try await Task.sleep(for: .milliseconds(150))
        precondition(abs(recording.elapsed - 0.4) < 0.001 && abs(recording.remaining - 0.85) < 0.001)
        let feedback = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("status.json"))) as! [String: Any]
        precondition(feedback["durationIsEstimate"] as? Bool == false)
        precondition(feedback["clockSource"] as? String == "AVAudioPlayer.currentTime")
        precondition(!events.contains("ensurePaused"), "Recording must not finish before player completion")
        // Settings are snapshotted per take; editing them cannot alter an in-flight finishing action.
        recording.settings.after = .none
        fake.completion?(true)
        await take.value
        precondition(recording.phase == "completed" && !recording.isBusy && recording.remaining == 0)
        precondition(events == ["startCue", "ensureRecording", "verifyRecording", "play", "neon", "inputIdle", "ensurePaused", "stopCue"], events.description)
        // Failed recorder confirmation must not play audio; make a safe cleanup attempt.
        events = []; fake = FakeWAVPlayer(); recording.settings = .init()
        recording.performAction = { action in
            events.append(action.rawValue)
            return action == .ensureRecording ? "FocuSee could not start" : nil
        }
        await recording.start(audio: Data(), takeID: UUID())?.value
        precondition(!fake.didPlay && recording.phase == "failed")
        precondition(events.contains("ensurePaused"))
        recording.performAction = { action in events.append(action.rawValue); return nil }
        recording.recordingState = { .unknown }
        events = []; fake = FakeWAVPlayer()
        await recording.start(audio: Data(), takeID: UUID())?.value
        precondition(!fake.didPlay && recording.phase == "failed")
        // Explicit cancellation stops the WAV and pauses an active cloned take.
        recording.recordingState = { .recording }
        events = []; fake = FakeWAVPlayer()
        let cancelled = recording.start(audio: Data(), takeID: UUID())!
        try await waitFor { fake.didPlay }
        let oldCompletion = fake.completion
        recording.cancel()
        await cancelled.value
        precondition(fake.didStop && recording.phase == "cancelled" && events.contains("ensurePaused"))
        // A macOS speech takeover stops cloned audio without sending a late pause into its new recording.
        events = []; fake = FakeWAVPlayer()
        let interrupted = recording.start(audio: Data(), takeID: UUID())!
        try await waitFor { fake.didPlay }
        oldCompletion?(true)
        try await Task.sleep(for: .milliseconds(20))
        precondition(recording.phase == "playing", "Old completion must not finish a later take")
        recording.cancel(pauseRecording: false)
        await interrupted.value
        precondition(!events.contains("ensurePaused"))
        // No-action mode ignores delays and optional waits, matching existing shortcut behavior.
        recording.settings.before = .none; recording.settings.after = .none
        recording.settings.delayBefore = 10; recording.settings.delayAfter = 10
        events = []; fake = FakeWAVPlayer()
        let noActions = recording.start(audio: Data(), takeID: UUID())!
        try await waitFor { fake.didPlay }
        fake.completion?(true)
        await noActions.value
        precondition(recording.phase == "completed" && events == ["none", "none"])
        // A player start failure cannot hang a take or leave it without a cleanup pause attempt.
        recording.settings = .init(); fake = FakeWAVPlayer(); fake.playSucceeds = false; events = []
        await recording.start(audio: Data(), takeID: UUID())?.value
        precondition(recording.phase == "failed" && !recording.isBusy && events.contains("ensurePaused"))
        recording.speechIsIdle = { false }; fake = FakeWAVPlayer(); events = []
        precondition(recording.start(audio: Data(), takeID: UUID()) == nil && !fake.didPlay && events.isEmpty)
        print("PASS: original-clock progress, completion-driven finishing, delay/wait order, settings persistence/snapshot, failed confirmation, cancellation cleanup, macOS takeover, stale completion, duplicate suppression and no-action behavior; no recorder or real audio used")
    }
}
