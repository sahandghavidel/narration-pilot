import Foundation

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
    case pressed, held, released, cancelled
}

@MainActor
final class SharedBackRoutingService {
    private final class Request {
        private var completion: ((SharedBackOwner) -> Void)?
        init(_ completion: @escaping (SharedBackOwner) -> Void) { self.completion = completion }
        func finish(_ owner: SharedBackOwner) {
            let callback = completion
            completion = nil
            callback?(owner)
        }
    }

    // Resolve away from the event tap, using fresh Accessibility data instead
    // of a periodically cached state. Slow or inaccessible apps fail closed.
    func resolve(_ completion: @escaping (SharedBackOwner) -> Void) {
        let request = Request(completion)
        Task {
            let state = await Task.detached(priority: .userInitiated) {
                FocuSeeAccessibilityService().recordingState()
            }.value
            request.finish(SharedBackOwner(state: state))
        }
        Task {
            try? await Task.sleep(for: .milliseconds(1500))
            request.finish(.blocked)
        }
    }

    static func forward(_ phase: SharedBackPhase, id: String, duration: TimeInterval, middle: Bool = false) {
        func send() {
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name(middle ? "local.clipboardreadermac.sharedMiddle.v1" : "local.clipboardreadermac.sharedBack.v2"),
                object: "local.clipboardreadermac",
                userInfo: ["version": middle ? 1 : 2, "phase": phase.rawValue, "id": id,
                           "duration": duration, "owner": "neonSpotlight",
                           "sentAt": ProcessInfo.processInfo.systemUptime],
                deliverImmediately: true)
        }
        send()
        // Idempotent end messages are retried; the receiver also times out a
        // held press if heartbeats cease, even while Narration Pilot is alive.
        if phase == .released || phase == .cancelled {
            for delay in [0.1, 0.25] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { send() }
            }
        }
    }
}
