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
        let plainBack: Bool
    }
    private struct Pending {
        let id: UUID
        let work: DispatchWorkItem
        let double: MouseShortcutAction
        let click: MouseShortcutAction
        let deadline: TimeInterval
        let plainBack: Bool
    }
    private final class BackPress {
        let id = UUID().uuidString
        let started: TimeInterval
        let click: MouseShortcutAction
        let hold: MouseShortcutAction
        let double: MouseShortcutAction
        var owner: SharedBackOwner?
        var releasedAt: TimeInterval?
        var began = false
        var firstClick: Pending?
        init(started: TimeInterval, click: MouseShortcutAction, hold: MouseShortcutAction, double: MouseShortcutAction) {
            self.started = started; self.click = click; self.hold = hold; self.double = double
        }
    }
    private enum Lane { case shared, normal(Int64) }
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retryTimer: Timer?
    private var heartbeatTimer: Timer?
    private var held: [Int64: Press] = [:]
    private var active: [Int64: Lane] = [:]
    private var pending: [Int64: Pending] = [:]
    private var backQueue: [Int64: [BackPress]] = [:]
    private var generation = 0
    private var fnKeyIsDown = false
    private static let doubleClickWindow: TimeInterval = 0.3
    private let defaults: UserDefaults
    private let resolveBackOwner: (@escaping (SharedBackOwner) -> Void) -> Void
    private let forwardBack: (SharedBackPhase, String, TimeInterval) -> Void
    private let forwardMiddle: (SharedBackPhase, String, TimeInterval) -> Void
    private let action: (MouseShortcutAction) -> Void

    init(defaults: UserDefaults = .standard,
         resolveBackOwner: @escaping (@escaping (SharedBackOwner) -> Void) -> Void = { $0(.narration) },
         forwardBack: @escaping (SharedBackPhase, String, TimeInterval) -> Void = { phase, id, duration in
             SharedBackRoutingService.forward(phase, id: id, duration: duration)
         }, forwardMiddle: @escaping (SharedBackPhase, String, TimeInterval) -> Void = { phase, id, duration in
             SharedBackRoutingService.forward(phase, id: id, duration: duration, middle: true)
         }, action: @escaping (MouseShortcutAction) -> Void) {
        self.defaults = defaults; self.resolveBackOwner = resolveBackOwner
        self.forwardBack = forwardBack; self.forwardMiddle = forwardMiddle; self.action = action
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
                    service.cancelGestures()
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
            if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil; tap = nil
        cancelGestures()
        start()
    }

    private func cancelGestures() {
        generation += 1
        for (identity, presses) in backQueue {
            for press in presses where press.began && press.owner == .neonSpotlight {
                forwardShared(identity, .cancelled, press.id, 0)
            }
        }
        heartbeatTimer?.invalidate(); heartbeatTimer = nil
        pending.values.forEach { $0.work.cancel() }
        pending.removeAll(); held.removeAll(); active.removeAll(); backQueue.removeAll()
        fnKeyIsDown = false
    }

    func stop() {
        retryTimer?.invalidate(); retryTimer = nil
        cancelGestures()
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil; tap = nil
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
        let now = ProcessInfo.processInfo.systemUptime
        let down = type == .keyDown || type == .otherMouseDown
        if !down {
            guard let lane = active.removeValue(forKey: identity) else { return false }
            switch lane {
            case .shared:
                backQueue[identity]?.last?.releasedAt = now
                pumpBack(identity)
            case .normal(let key): finishPress(key, endedAt: now)
            }
            return true
        }
        if active[identity] != nil { return true }
        let modifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]
        guard event.flags.intersection(modifiers).isEmpty else { return false }
        if (button == 3 || button == 2) && !fnKeyIsDown {
            let press = BackPress(started: now,
                click: (button == 2 ? MouseShortcutGesture.middleClick : .backClick).action(in: defaults),
                hold: (button == 2 ? MouseShortcutGesture.middleHold : .backHold).action(in: defaults),
                double: (button == 2 ? MouseShortcutGesture.middleDouble : .backDouble).action(in: defaults))
            press.firstClick = takePending(identity, pressedAt: now)
            backQueue[identity, default: []].append(press)
            active[identity] = .shared
            resolveBackOwner { [weak self, weak press] owner in
                guard let self, let press, self.backQueue[identity]?.contains(where: { $0 === press }) == true else { return }
                press.owner = owner
                self.pumpBack(identity)
            }
            return true
        }
        let key = fnKeyIsDown ? identity + 20_000 : identity
        if fnKeyIsDown {
            let gesture: MouseShortcutGesture = button == 2 ? .fnMiddle : (button == 3 ? .fnBack : .fnForward)
            let selected = gesture.action(in: defaults)
            guard selected != .none else { return false }
            held[key] = Press(started: now, click: selected, hold: .none, double: .none, isSecond: false, isFn: true, plainBack: false)
        } else {
            let click: MouseShortcutGesture = button == 2 ? .middleClick : .forwardClick
            let hold: MouseShortcutGesture = button == 2 ? .middleHold : .forwardHold
            let double: MouseShortcutGesture = button == 2 ? .middleDouble : .forwardDouble
            let c = click.action(in: defaults), h = hold.action(in: defaults), d = double.action(in: defaults)
            let first = takePending(key, pressedAt: now)
            guard first != nil || c != .none || h != .none || d != .none else { return false }
            held[key] = Press(started: now, click: c, hold: h, double: first?.double ?? d,
                isSecond: first != nil, isFn: false, plainBack: false)
        }
        active[identity] = .normal(key)
        return true
    }

    private func takePending(_ identity: Int64, pressedAt: TimeInterval) -> Pending? {
        guard let first = pending.removeValue(forKey: identity) else { return nil }
        first.work.cancel()
        if pressedAt >= first.deadline {
            dispatch(first.click, plainBack: first.plainBack)
            return nil
        }
        return first
    }

    private func forwardShared(_ identity: Int64, _ phase: SharedBackPhase, _ id: String, _ duration: TimeInterval) {
        if identity == 2 || identity == 1113 { forwardMiddle(phase, id, duration) }
        else { forwardBack(phase, id, duration) }
    }

    private func pumpBack(_ identity: Int64) {
        while let press = backQueue[identity]?.first {
            // Pause an eligible first-click timer as soon as the next press is
            // known, even while its fresh Accessibility decision is in flight.
            if press.firstClick == nil { press.firstClick = takePending(identity, pressedAt: press.started) }
            guard let owner = press.owner else { return }
            if !press.began {
                press.began = true
                switch owner {
                case .narration:
                    held[identity] = Press(started: press.started, click: press.click, hold: press.hold,
                        double: press.firstClick?.double ?? press.double, isSecond: press.firstClick != nil,
                        isFn: false, plainBack: true)
                case .neonSpotlight:
                    forwardShared(identity, .pressed, press.id, (press.releasedAt ?? ProcessInfo.processInfo.systemUptime) - press.started)
                    startHeartbeat()
                case .blocked: break
                }
            }
            guard let ended = press.releasedAt else { return }
            switch owner {
            case .narration: finishPress(identity, endedAt: ended)
            case .neonSpotlight: forwardShared(identity, .released, press.id, ended - press.started)
            case .blocked: break
            }
            backQueue[identity]?.removeFirst()
            if backQueue[identity]?.isEmpty == true { backQueue.removeValue(forKey: identity) }
        }
    }

    private func startHeartbeat() {
        guard heartbeatTimer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sendHeartbeats() }
        }
        heartbeatTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func sendHeartbeats() {
        var any = false
        for (identity, queue) in backQueue {
            for press in queue where press.began && press.owner == .neonSpotlight && press.releasedAt == nil {
                any = true
                forwardShared(identity, .held, press.id, ProcessInfo.processInfo.systemUptime - press.started)
            }
        }
        if !any { heartbeatTimer?.invalidate(); heartbeatTimer = nil }
    }

    private func finishPress(_ key: Int64, endedAt: TimeInterval) {
        guard let press = held.removeValue(forKey: key) else { return }
        if press.isFn { dispatch(press.click, plainBack: false); return }
        let duration = endedAt - press.started
        if duration >= MouseShortcutResolution.holdThreshold {
            dispatch(press.hold, plainBack: press.plainBack)
        } else if press.isSecond {
            dispatch(press.double, plainBack: press.plainBack)
        } else if press.double == .none {
            dispatch(press.click, plainBack: press.plainBack)
        } else {
            let id = UUID()
            let deadline = endedAt + Self.doubleClickWindow
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.pending[key]?.id == id else { return }
                self.pending.removeValue(forKey: key)
                self.dispatch(press.click, plainBack: press.plainBack)
            }
            pending[key] = Pending(id: id, work: work, double: press.double, click: press.click,
                deadline: deadline, plainBack: press.plainBack)
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline - ProcessInfo.processInfo.systemUptime), execute: work)
        }
    }

    private func dispatch(_ chosen: MouseShortcutAction, plainBack: Bool) {
        guard chosen != .none else { return }
        let expectedGeneration = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == expectedGeneration else { return }
            if plainBack {
                // A press may have begun while paused, then wait for a hold or
                // double-click. Recheck before any configured action, including
                // Stop/Read/Toggle, can affect a newly started recording.
                self.resolveBackOwner { [weak self] owner in
                    guard let self, owner == .narration, self.generation == expectedGeneration else { return }
                    self.action(chosen)
                }
            } else { self.action(chosen) }
        }
    }
}
