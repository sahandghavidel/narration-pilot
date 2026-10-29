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
        let service = MouseShortcutService(defaults: defaults, resolveBackOwner: { $0(owner) }, forwardBack: { phase, id, _ in
            phases.append(phase); ids.append(id)
        }) { actions.append($0) }
        func event(_ down: Bool, flags: CGEventFlags = .maskSecondaryFn) -> Bool {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: 105, keyDown: down)!
            e.flags = flags
            return service.handle(down ? .keyDown : .keyUp, e)
        }
        func drain(_ delay: Double = 0.03) { RunLoop.main.run(until: Date().addingTimeInterval(delay)) }
        precondition(SharedBackOwner(state: .recording) == .neonSpotlight)
        precondition(SharedBackOwner(state: .paused) == .narration)
        precondition(SharedBackOwner(state: .notRunning) == .narration)
        precondition(SharedBackOwner(state: .notRecording) == .narration)
        precondition(SharedBackOwner(state: .unknown) == .blocked)
        precondition(event(true)); precondition(event(false)); drain()
        precondition(actions == [.replay] && phases.isEmpty); actions.removeAll()
        // The chosen owner never changes during a press, but a narration action
        // is suppressed if recording starts before that action can execute.
        precondition(event(true)); owner = .neonSpotlight; precondition(event(false)); drain()
        precondition(actions.isEmpty && phases.isEmpty)
        precondition(event(true)); owner = .narration; precondition(event(false)); drain()
        precondition(actions.isEmpty && phases == [.pressed, .released] && ids[0] == ids[1])
        phases.removeAll(); ids.removeAll()
        owner = .blocked
        precondition(event(true)); owner = .narration; precondition(event(false)); drain()
        precondition(actions.isEmpty && phases.isEmpty)
        precondition(!event(true, flags: [.maskCommand, .maskSecondaryFn]))
        precondition(!event(false, flags: [.maskCommand, .maskSecondaryFn]))
        defaults.set("next", forKey: MouseShortcutGesture.backDouble.key)
        defaults.set("stop", forKey: MouseShortcutGesture.backClick.key)
        precondition(event(true)); precondition(event(false))
        owner = .neonSpotlight
        drain(0.4)
        precondition(actions.isEmpty) // queued Stop cannot interrupt recording
        precondition(event(true)); service.stop(); drain()
        precondition(phases == [.pressed, .cancelled]); phases.removeAll()

        // Back events can complete before the AX query returns. Two such presses
        // must remain a double-click, without a leaked single or hold action.
        var completions: [(SharedBackOwner) -> Void] = []
        let delayed = MouseShortcutService(defaults: defaults,
            resolveBackOwner: { completions.append($0) }, forwardBack: { _,_,_ in }) { actions.append($0) }
        for down in [true, false, true, false] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: 105, keyDown: down)!
            precondition(delayed.handle(down ? .keyDown : .keyUp, e))
        }
        precondition(completions.count == 2)
        completions.removeFirst()(.narration)
        completions.removeFirst()(.narration)
        drain()
        precondition(completions.count == 1)
        completions.removeFirst()(.narration)
        drain(0.4)
        precondition(actions == [.next])
        delayed.stop()
        print("Fresh ownership, queued-action suppression, state changes, delayed-resolution double clicks and shutdown checks passed")
    }
}
