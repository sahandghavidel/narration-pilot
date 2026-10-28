@preconcurrency import CoreGraphics
import Foundation

@MainActor
final class MouseShortcutService {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var held = Set<Int64>()
    private let action: (Int64) -> Void

    init(action: @escaping (Int64) -> Void) { self.action = action }

    func start() {
        guard tap == nil else { return }
        let mask = [CGEventType.otherMouseDown, .otherMouseUp, .keyDown, .keyUp]
            .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return MainActor.assumeIsolated {
                let service = Unmanaged<MouseShortcutService>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    service.held.removeAll()
                    if let tap = service.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                return service.handle(type, event) ? nil : Unmanaged.passUnretained(event)
            }
        }
        tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return }
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let keyboard = type == .keyDown || type == .keyUp
        let raw = event.getIntegerValueField(keyboard ? .keyboardEventKeycode : .mouseEventButtonNumber)
        let button: Int64
        if keyboard {
            guard raw == 105 || raw == 107 else { return false }
            button = raw == 105 ? 3 : 4
        } else {
            guard raw == 3 || raw == 4 else { return false }
            button = raw
        }
        let identity = keyboard ? raw + 1000 : raw
        let down = type == .keyDown || type == .otherMouseDown
        if down {
            if held.contains(identity) { return true }
            let modifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]
            guard event.flags.intersection(modifiers).isEmpty else { return false }
            held.insert(identity)
            DispatchQueue.main.async { [action] in action(button) }
            return true
        }
        return held.remove(identity) != nil
    }
}
