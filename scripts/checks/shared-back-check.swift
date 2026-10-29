import Foundation
import CoreGraphics

@main struct SharedBackCheck {
    @MainActor static func main() {
        let suite = "SharedBackCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var owner = SharedBackOwner.narration
        var actions: [MouseShortcutAction] = []
        var phases: [SharedBackPhase] = []
        var ids: [String] = []
        let service = MouseShortcutService(defaults: defaults, backOwner: { owner }, forwardBack: { phase, id, _ in
            phases.append(phase); ids.append(id)
        }) { actions.append($0) }
        func event(_ down: Bool, code: CGKeyCode = 105, flags: CGEventFlags = .maskSecondaryFn) -> Bool {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
            e.flags = flags
            return service.handle(down ? .keyDown : .keyUp, e)
        }
        func drain(_ delay: Double = 0.03) { RunLoop.main.run(until: Date().addingTimeInterval(delay)) }
        precondition(SharedBackOwner(state: .recording) == .neonSpotlight)
        precondition(SharedBackOwner(state: .paused) == .narration)
        precondition(SharedBackOwner(state: .notRunning) == .narration)
        precondition(SharedBackOwner(state: .notRecording) == .narration)
        precondition(SharedBackOwner(state: .unknown) == .blocked)
        precondition(event(true)); owner = .neonSpotlight; precondition(event(false)); drain()
        precondition(actions == [.replay] && phases.isEmpty)
        actions.removeAll()
        precondition(event(true)); owner = .narration; precondition(event(false)); drain()
        precondition(actions.isEmpty && phases == [.pressed, .released] && ids[0] == ids[1])
        phases.removeAll(); ids.removeAll()
        owner = .blocked
        precondition(event(true)); owner = .narration; precondition(event(false)); drain()
        precondition(actions.isEmpty && phases.isEmpty)
        precondition(!event(true, flags: [.maskCommand, .maskSecondaryFn]))
        precondition(!event(false, flags: [.maskCommand, .maskSecondaryFn]))
        // A delayed narration single-click cannot fire after a new Neon press.
        defaults.set("next", forKey: MouseShortcutGesture.backDouble.key)
        precondition(event(true)); precondition(event(false))
        owner = .neonSpotlight
        precondition(event(true)); precondition(event(false)); drain(0.4)
        precondition(actions.isEmpty && phases == [.pressed, .released])
        phases.removeAll()
        precondition(event(true)); service.stop(); drain()
        precondition(phases == [.pressed, .cancelled])
        print("Shared Back owner, state changes during press, delayed-click cancellation, Command pass-through and shutdown checks passed")
    }
}
