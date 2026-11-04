import AppKit
import Foundation

/// Local, opt-in feedback. No credentials, network server, or remote mutations.
@MainActor
final class AgentFeedbackPublisher: ObservableObject {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/local.clipboardreadermac/AgentFeedback")
    static let statusURL = directory.appendingPathComponent("status.json")
    private let defaults: UserDefaults
    let outputDirectory: URL
    var statusURL: URL { outputDirectory.appendingPathComponent("status.json") }
    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: "agentFeedback.enabled")
            if !enabled { try? FileManager.default.removeItem(at: statusURL) }
            refresh?()
        }
    }
    @Published private(set) var summary = "Feedback disabled"
    @Published private(set) var sceneSummary = "No scene loaded"
    @Published private(set) var latestTakeSummary = "No takes this session"
    @Published private(set) var latestError: String?
    @Published private(set) var writeError: String?
    var refresh: (() -> Void)?
    private var timer: Timer?
    private var observing = false
    private var observedState = "unknown"
    private var observedAt: Date?
    private var events: [[String: String]] = []
    private var take: [String: Any]?
    private var history: [[String: Any]] = []
    private var stage = "idle"
    private var requestedRecordingState: String?
    private(set) var lastData: Data?
    private var lastSpeech = "idle"
    private var takeIssues: [String] = []
    private var elapsed: TimeInterval = 0
    private var lastTick = Date()

    init(defaults: UserDefaults = .standard, directory: URL = AgentFeedbackPublisher.directory) {
        self.defaults = defaults
        outputDirectory = directory
        enabled = defaults.bool(forKey: "agentFeedback.enabled")
    }

    func start(refresh: @escaping () -> Void) {
        self.refresh = refresh
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        tick()
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if take != nil { finish("interrupted", error: "Application terminated") }
        guard enabled, let data = lastData,
              var payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        payload["appRunning"] = false
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: statusURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: statusURL.path)
        }
    }

    func observe(_ state: FocuSeeRecordingState) {
        observedState = String(describing: state)
        observedAt = Date()
        event("focuseeObserved", observedState)
        refresh?()
    }

    private func tick() {
        guard enabled else { return }
        refresh?()
        guard !observing else { return }
        observing = true
        let started = Date()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let state = FocuSeeAccessibilityService().recordingState()
            Task { @MainActor [weak self] in
                guard let self else { return }
                observing = false
                if let observedAt, started < observedAt { return }
                let value = Date().timeIntervalSince(started) < 1.5 ? String(describing: state) : "unknown"
                if observedState != value { event("focuseeObserved", value) }
                if lastSpeech == "speaking", take?["recordingExpected"] as? Bool == true, value != "recording" {
                    let issue = "FocuSee observed as \(value) during narration"
                    if !takeIssues.contains(issue) { takeIssues.append(issue); event("recordingIssue", issue) }
                    take?["issues"] = takeIssues
                }
                observedState = value
                observedAt = Date()
                refresh?()
            }
        }
    }

    func begin(id: UUID, scene: [String: Any], recordingExpected: Bool) {
        if take != nil { finish("cancelled", error: "Replaced by another read sequence") }
        elapsed = 0
        takeIssues = []
        requestedRecordingState = nil
        take = ["id": id.uuidString, "scene": scene, "recordingExpected": recordingExpected,
                "startedAt": stamp(), "stage": "preparing"]
        transition("preparing")
    }

    func transition(_ value: String) {
        if value == "recordingRequested" { requestedRecordingState = "recording" }
        if value == "pauseRequested" { requestedRecordingState = "paused" }
        stage = value
        take?["stage"] = value
        event("stage", value)
        refresh?()
    }

    func finish(_ result: String, error: String? = nil) {
        guard var finished = take else { return }
        finished["result"] = result
        finished["issues"] = takeIssues
        finished["requiresReview"] = !takeIssues.isEmpty || error != nil || ["failed", "cancelled", "interrupted"].contains(result)
        latestTakeSummary = result
        latestError = error ?? takeIssues.last
        finished["endedAt"] = stamp()
        finished["error"] = error
        finished["elapsedSpeakingSeconds"] = elapsed
        history.append(finished)
        history = Array(history.suffix(20))
        take = nil
        stage = result
        event("takeFinished", error.map { "\(result): \($0)" } ?? result)
        refresh?()
    }

    func publish(scene: [String: Any], speech: String, passage: String, word: String,
                 estimatedDuration: Double, message: String) {
        let now = Date()
        if lastSpeech == "speaking" { elapsed += min(2, now.timeIntervalSince(lastTick)) }
        lastTick = now
        if lastSpeech != speech { event("speech", speech) }
        lastSpeech = speech
        if speech == "speaking", take != nil, ["startingNarration", "narrationPaused"].contains(stage) { transitionWithoutRefresh("narrating") }
        if speech == "paused", stage == "narrating" { transitionWithoutRefresh("narrationPaused") }
        sceneSummary = "\(scene["scriptTitle"] as? String ?? "Script") · Scene \(scene["sceneIndex"] as? Int ?? 0)"
        var payload: [String: Any] = [
            "schemaVersion": 1, "enabled": enabled, "appRunning": true,
            "pid": ProcessInfo.processInfo.processIdentifier, "updatedAt": stamp(),
            "staleAfterSeconds": 4, "currentScene": scene,
            "narration": ["state": speech, "passage": passage, "currentWord": word,
                          "elapsedSpeakingSeconds": elapsed, "elapsedScope": "currentOrLastReadSequence", "estimatedDurationSeconds": estimatedDuration,
                          "durationIsEstimate": true] as [String: Any],
            "focuSee": ["observedState": observedAt.map { now.timeIntervalSince($0) < 4 } == true ? observedState : "unknown",
                        "observedAt": observedAt.map { stamp($0) } ?? "",
                        "requestedState": requestedRecordingState as Any? ?? NSNull(), "source": "accessibility",
                        "verifiesSavedFootage": false] as [String: Any],
            "stage": stage, "message": message, "events": events, "recentTakes": history
        ]
        payload["activeTake"] = take ?? NSNull()
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else { return }
        lastData = data
        summary = "\(speech) · FocuSee: \(observedState) · \(stage)"
        guard enabled else { return }
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            try data.write(to: statusURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: statusURL.path)
            writeError = nil
        } catch { writeError = error.localizedDescription }
    }

    func copySnapshot() {
        refresh?()
        guard let lastData, let text = String(data: lastData, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func openFolder() {
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        NSWorkspace.shared.open(outputDirectory)
    }

    private func transitionWithoutRefresh(_ value: String) {
        stage = value; take?["stage"] = value; event("stage", value)
    }
    private func event(_ name: String, _ detail: String) {
        events.append(["at": stamp(), "name": name, "detail": detail])
        events = Array(events.suffix(100))
    }
    private func stamp(_ date: Date = Date()) -> String { ISO8601DateFormatter().string(from: date) }
}
