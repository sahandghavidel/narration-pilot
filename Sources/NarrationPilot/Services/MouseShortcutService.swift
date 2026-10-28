@preconcurrency import CoreGraphics
import Foundation

enum MouseShortcutAction: String, CaseIterable, Identifiable {
    case none, read, replay, onScreen, code, previous, next, restart, stop, pauseResume, overlay, openSceneManager, openFocusAndPlay
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "None"
        case .read: "Read Current Input"
        case .replay: "Replay Scene"
        case .onScreen: "Replay On Screen Only"
        case .code: "Replay Code Only"
        case .previous: "Previous Scene"
        case .next: "Next Scene"
        case .restart: "Restart Script"
        case .stop: "Stop Reading"
        case .pauseResume: "Pause / Resume"
        case .overlay: "Toggle Overlay"
        case .openSceneManager: "Open Scene Manager"
        case .openFocusAndPlay: "Open, Focus & Play"
        }
    }
}

enum MouseShortcutGesture: String, CaseIterable {
    case backClick, backHold, forwardClick, forwardHold, middleClick, middleHold
    var key: String { "clipboardReader.mouseShortcut.\(rawValue)" }
    var defaultAction: MouseShortcutAction {
        switch self {
        case .backClick: .replay
        case .forwardClick: .read
        case .middleClick: .onScreen
        case .middleHold: .openSceneManager
        case .backHold, .forwardHold: .none
        }
    }
    func action(in defaults: UserDefaults) -> MouseShortcutAction {
        guard let value = defaults.string(forKey: key) else { return defaultAction }
        return MouseShortcutAction(rawValue: value) ?? defaultAction
    }
}

enum MouseShortcutResolution {
    static let holdThreshold: TimeInterval = 0.6
    static func action(click: MouseShortcutAction, hold: MouseShortcutAction, duration: TimeInterval) -> MouseShortcutAction {
        duration >= holdThreshold ? hold : click
    }
}

@MainActor
final class MouseShortcutService {
    private struct Press {
        let started: TimeInterval
        let click: MouseShortcutAction
        let hold: MouseShortcutAction
    }
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var held: [Int64: Press] = [:]
    private let defaults: UserDefaults
    private let action: (MouseShortcutAction) -> Void

    init(defaults: UserDefaults = .standard, action: @escaping (MouseShortcutAction) -> Void) {
        self.defaults = defaults
        self.action = action
    }

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
            guard raw == 2 || raw == 3 || raw == 4 else { return false }
            button = raw
        }
        let identity = keyboard ? raw + 1000 : raw
        let down = type == .keyDown || type == .otherMouseDown
        if down {
            if held[identity] != nil { return true }
            let modifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]
            guard event.flags.intersection(modifiers).isEmpty else { return false }
            let gestures: (MouseShortcutGesture, MouseShortcutGesture)
            switch button {
            case 2: gestures = (.middleClick, .middleHold)
            case 3: gestures = (.backClick, .backHold)
            default: gestures = (.forwardClick, .forwardHold)
            }
            let click = gestures.0.action(in: defaults)
            let hold = gestures.1.action(in: defaults)
            guard click != .none || hold != .none else { return false }
            held[identity] = Press(started: ProcessInfo.processInfo.systemUptime, click: click, hold: hold)
            return true
        }
        guard let press = held.removeValue(forKey: identity) else { return false }
        let chosen = MouseShortcutResolution.action(click: press.click, hold: press.hold,
            duration: ProcessInfo.processInfo.systemUptime - press.started)
        if chosen != .none { DispatchQueue.main.async { [action] in action(chosen) } }
        return true
    }
}
