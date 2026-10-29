@preconcurrency import CoreGraphics
import Foundation

enum MouseShortcutAction: String, CaseIterable, Identifiable {
    case none, read, replay, onScreen, code, previous, next, restart, stop, pauseResume, overlay, openSceneManager, openFocusAndPlay, toggleRecording, clipboardAlwaysOne, clipboardAlwaysTwo
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "None"
        case .read: "Read Current Input"
        case .clipboardAlwaysOne: "Read Clipboard Always 1"
        case .clipboardAlwaysTwo: "Read Clipboard Always 2"
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
        case .toggleRecording: "Toggle FocuSee Recording"
        }
    }
}

enum MouseShortcutGesture: String, CaseIterable {
    case backClick, backHold, backDouble, forwardClick, forwardHold, forwardDouble, middleClick, middleHold, middleDouble
    case fnBack, fnForward, fnMiddle
    var key: String { "clipboardReader.mouseShortcut.\(rawValue)" }
    var defaultAction: MouseShortcutAction {
        switch self {
        case .backClick: .replay
        case .forwardClick: .read
        case .middleClick: .onScreen
        case .middleHold: .openSceneManager
        case .backHold, .forwardHold, .backDouble, .forwardDouble, .middleDouble, .fnBack, .fnForward, .fnMiddle: .none
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
        let double: MouseShortcutAction
        let isSecond: Bool
        let isFn: Bool
    }
    private struct Pending {
        let work: DispatchWorkItem
        let double: MouseShortcutAction
        let click: MouseShortcutAction
        let deadline: TimeInterval
    }
    private struct BackPress {
        let owner: SharedBackOwner
        let id: String
        let started: TimeInterval
    }
    private var sharedBackHeld: [Int64: BackPress] = [:]
    private let backOwner: () -> SharedBackOwner
    private let forwardBack: (SharedBackPhase, String, TimeInterval) -> Void
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retryTimer: Timer?
    private var held: [Int64: Press] = [:]
    private var pending: [Int64: Pending] = [:]
    private var fnKeyIsDown = false
    private static let doubleClickWindow: TimeInterval = 0.3
    private let defaults: UserDefaults
    private let action: (MouseShortcutAction) -> Void

    init(defaults: UserDefaults = .standard,
         backOwner: @escaping () -> SharedBackOwner = { .narration },
         forwardBack: @escaping (SharedBackPhase, String, TimeInterval) -> Void = { phase, id, duration in
             SharedBackRoutingService.forward(phase, id: id, duration: duration)
         },
         action: @escaping (MouseShortcutAction) -> Void) {
        self.backOwner = backOwner
        self.forwardBack = forwardBack
        self.defaults = defaults
        self.action = action
    }

    func start() {
        if retryTimer == nil {
            retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshListener() }
            }
        }
        guard tap == nil else { return }
        let mask = [CGEventType.otherMouseDown, .otherMouseUp, .keyDown, .keyUp, .flagsChanged]
            .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return MainActor.assumeIsolated {
                let service = Unmanaged<MouseShortcutService>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    service.cancelForwardedBackPresses()
                    service.held.removeAll()
                    service.fnKeyIsDown = false
                    service.pending.values.forEach { $0.work.cancel() }
                    service.pending.removeAll()
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

    private func refreshListener() {
        if let tap, CFMachPortIsValid(tap) {
            if !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        tap = nil
        cancelForwardedBackPresses()
        held.removeAll()
        fnKeyIsDown = false
        pending.values.forEach { $0.work.cancel() }
        pending.removeAll()
        start()
    }

    private func cancelForwardedBackPresses() {
        for press in sharedBackHeld.values where press.owner == .neonSpotlight {
            forwardBack(.cancelled, press.id, 0)
        }
        sharedBackHeld.removeAll()
    }

    func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        cancelForwardedBackPresses()
        pending.values.forEach { $0.work.cancel() }
        pending.removeAll()
        held.removeAll()
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
    }

    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .flagsChanged {
            if event.getIntegerValueField(.keyboardEventKeycode) == 63 {
                fnKeyIsDown = event.flags.contains(.maskSecondaryFn)
            }
            return false
        }
        let keyboard = type == .keyDown || type == .keyUp
        let raw = event.getIntegerValueField(keyboard ? .keyboardEventKeycode : .mouseEventButtonNumber)
        let button: Int64
        if keyboard {
            guard raw == 105 || raw == 107 || raw == 113 else { return false }
            button = raw == 113 ? 2 : (raw == 105 ? 3 : 4)
        } else {
            guard raw == 2 || raw == 3 || raw == 4 else { return false }
            button = raw
        }
        let identity = keyboard ? raw + 1000 : raw
        let down = type == .keyDown || type == .otherMouseDown
        // Ownership is chosen once on down and retained even if recording or
        // modifier state changes while this physical press remains held.
        if let press = sharedBackHeld[identity] {
            if down {
                if press.owner != .narration { return true }
            } else {
                sharedBackHeld.removeValue(forKey: identity)
                if press.owner == .neonSpotlight {
                    forwardBack(.released, press.id, ProcessInfo.processInfo.systemUptime - press.started)
                    return true
                }
                if press.owner == .blocked { return true }
            }
        }
        if down {
            if held[identity] != nil { return true }
            let modifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]
            guard event.flags.intersection(modifiers).isEmpty else { return false }
            if button == 3 && !fnKeyIsDown && sharedBackHeld[identity] == nil {
                let owner = backOwner()
                let press = BackPress(owner: owner, id: UUID().uuidString, started: ProcessInfo.processInfo.systemUptime)
                sharedBackHeld[identity] = press
                if owner != .narration {
                    // A delayed single click must not cross into a new owner.
                    pending.removeValue(forKey: identity)?.work.cancel()
                    if owner == .neonSpotlight { forwardBack(.pressed, press.id, 0) }
                    return true
                }
            }
            if fnKeyIsDown {
                let gesture: MouseShortcutGesture = button == 2 ? .fnMiddle : (button == 3 ? .fnBack : .fnForward)
                let selected = gesture.action(in: defaults)
                guard selected != .none else { return false }
                held[identity] = Press(started: ProcessInfo.processInfo.systemUptime, click: selected,
                                       hold: .none, double: .none, isSecond: false, isFn: true)
                return true
            }
            let gestures: (MouseShortcutGesture, MouseShortcutGesture, MouseShortcutGesture)
            switch button {
            case 2: gestures = (.middleClick, .middleHold, .middleDouble)
            case 3: gestures = (.backClick, .backHold, .backDouble)
            default: gestures = (.forwardClick, .forwardHold, .forwardDouble)
            }
            let click = gestures.0.action(in: defaults)
            let hold = gestures.1.action(in: defaults)
            let double = gestures.2.action(in: defaults)
            var firstClick = pending.removeValue(forKey: identity)
            firstClick?.work.cancel()
            if let expired = firstClick, ProcessInfo.processInfo.systemUptime >= expired.deadline {
                if expired.click != .none { DispatchQueue.main.async { [action] in action(expired.click) } }
                firstClick = nil
            }
            guard firstClick != nil || click != .none || hold != .none || double != .none else { return false }
            held[identity] = Press(started: ProcessInfo.processInfo.systemUptime, click: click, hold: hold,
                                   double: firstClick?.double ?? double, isSecond: firstClick != nil, isFn: false)
            return true
        }
        guard let press = held.removeValue(forKey: identity) else { return false }
        if press.isFn {
            DispatchQueue.main.async { [action] in action(press.click) }
            return true
        }
        let duration = ProcessInfo.processInfo.systemUptime - press.started
        if duration >= MouseShortcutResolution.holdThreshold {
            if press.hold != .none { DispatchQueue.main.async { [action] in action(press.hold) } }
        } else if press.isSecond {
            DispatchQueue.main.async { [action] in action(press.double) }
        } else if press.double == .none {
            if press.click != .none { DispatchQueue.main.async { [action] in action(press.click) } }
        } else {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.pending.removeValue(forKey: identity) != nil else { return }
                if press.click != .none { self.action(press.click) }
            }
            pending[identity] = Pending(work: work, double: press.double, click: press.click,
                deadline: ProcessInfo.processInfo.systemUptime + Self.doubleClickWindow)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.doubleClickWindow, execute: work)
        }
        return true
    }
}
