import Foundation
import CoreGraphics

@main struct MiddleCheck {
    @MainActor static func main() {
        let suite = "MiddleCheck.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("openSceneManager", forKey: MouseShortcutGesture.middleClick.key)
        var owner = SharedBackOwner.neonSpotlight
        var actions: [MouseShortcutAction] = []
        var phases: [SharedBackPhase] = []
        var back = 0
        let service = MouseShortcutService(defaults: defaults, resolveBackOwner: { $0(owner) },
            forwardBack: { _,_,_ in back += 1 }, forwardMiddle: { p,_,_ in phases.append(p) }) { actions.append($0) }
        func press(_ down: Bool) {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: 113, keyDown: down)!
            e.flags = .maskSecondaryFn // automatic Karabiner flag is not physical Fn
            precondition(service.handle(down ? .keyDown : .keyUp, e))
        }
        func drain() { RunLoop.main.run(until: Date().addingTimeInterval(0.03)) }
        press(true); press(false); drain()
        precondition(phases == [.pressed, .released] && actions.isEmpty && back == 0)
        phases.removeAll()
        owner = .narration; press(true); press(false); drain()
        precondition(actions == [.openSceneManager] && phases.isEmpty)
        actions.removeAll()
        owner = .blocked; press(true); press(false); drain()
        precondition(phases.isEmpty && actions.isEmpty)
        owner = .narration; press(true); owner = .neonSpotlight; press(false); drain()
        precondition(phases.isEmpty && actions.isEmpty) // pending manager cannot open in recording
        service.stop()
        print("Middle F15 routes only recording gestures to Neon; unknown and recording transitions suppress narration actions")
    }
}
