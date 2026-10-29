import Foundation

// Only Narration Pilot decides who owns a plain Back press. Neon Spotlight receives
// that decision with the press rather than independently sampling recording state.
enum SharedBackOwner: Equatable {
    case narration, neonSpotlight, blocked

    init(state: FocuSeeRecordingState) {
        switch state {
        case .recording: self = .neonSpotlight
        case .paused, .notRecording, .notRunning: self = .narration
        case .unknown: self = .blocked
        }
    }
}

enum SharedBackPhase: String {
    case pressed, released, cancelled
}

@MainActor
final class SharedBackRoutingService {
    private var state: FocuSeeRecordingState = .unknown
    private var sampledAt: TimeInterval = 0
    private var task: Task<Void, Never>?

    var owner: SharedBackOwner {
        // Never route from a stale or incomplete Accessibility inspection.
        guard ProcessInfo.processInfo.systemUptime - sampledAt < 1.5 else { return .blocked }
        return SharedBackOwner(state: state)
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                let began = ProcessInfo.processInfo.systemUptime
                let state = await Task.detached(priority: .userInitiated) {
                    FocuSeeAccessibilityService().recordingState()
                }.value
                guard let self, !Task.isCancelled else { return }
                self.state = state
                self.sampledAt = began
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            }
        }
    }

    static func forward(_ phase: SharedBackPhase, id: String, duration: TimeInterval) {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("local.clipboardreadermac.sharedBack.v1"),
            object: "local.clipboardreadermac",
            userInfo: ["version": 1, "phase": phase.rawValue, "id": id,
                       "duration": duration, "owner": "neonSpotlight"],
            deliverImmediately: true
        )
    }
}
