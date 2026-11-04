import AppKit
import ApplicationServices
import Foundation

enum ApprovedAudioIdleResult { case idle, timedOut, unavailable }

/// Monotonic activity times, independent of transcription and recorder command latency.
struct ApprovedAudioIdleState {
    private(set) var lastActivity: TimeInterval
    private(set) var lastKeyboardActivity: TimeInterval

    init(now: TimeInterval, generalIdle: TimeInterval = 0, keyboardIdle: TimeInterval = 0) {
        lastActivity = now - max(0, generalIdle)
        lastKeyboardActivity = now - max(0, keyboardIdle)
    }

    mutating func observe(at time: TimeInterval, keyboard: Bool) {
        lastActivity = max(lastActivity, time)
        if keyboard { lastKeyboardActivity = max(lastKeyboardActivity, time) }
    }

    func remaining(at now: TimeInterval, quietPeriod: Double, keyboardQuietPeriod: Double) -> Double {
        max(0, quietPeriod - (now - lastActivity), keyboardQuietPeriod - (now - lastKeyboardActivity))
    }
}

@MainActor
final class ApprovedAudioIdleMonitor {
    private let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
        .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
        .scrollWheel, .keyDown, .keyUp, .flagsChanged]
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var state: ApprovedAudioIdleState?
    private var pointer = CGPoint.zero

    func start() -> Bool {
        stop()
        guard AXIsProcessTrusted() else { return false }
        let keyboardTypes: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        let allTypes = keyboardTypes + [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .scrollWheel]
        func idle(for types: [CGEventType]) -> TimeInterval {
            types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
                .filter { $0.isFinite && $0 >= 0 }.min() ?? 0
        }
        state = ApprovedAudioIdleState(now: ProcessInfo.processInfo.systemUptime,
            generalIdle: idle(for: allTypes), keyboardIdle: idle(for: keyboardTypes))
        pointer = NSEvent.mouseLocation
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            let type = event.type
            let location = NSEvent.mouseLocation
            let time = ProcessInfo.processInfo.systemUptime
            Task { @MainActor in self?.observe(type: type, location: location, time: time) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let type = event.type
            let location = NSEvent.mouseLocation
            let time = ProcessInfo.processInfo.systemUptime
            Task { @MainActor in self?.observe(type: type, location: location, time: time) }
            return event
        }
        guard globalMonitor != nil, localMonitor != nil else { stop(); return false }
        return true
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil; localMonitor = nil; state = nil
    }

    func waitUntilIdle(quietPeriod: Double, keyboardQuietPeriod: Double, maximumExtraWait: Double) async -> ApprovedAudioIdleResult {
        let started = ProcessInfo.processInfo.systemUptime
        while !Task.isCancelled {
            guard let state else { return .unavailable }
            let now = ProcessInfo.processInfo.systemUptime
            let remaining = state.remaining(at: now, quietPeriod: quietPeriod, keyboardQuietPeriod: keyboardQuietPeriod)
            if remaining <= 0 { return .idle }
            let limit = maximumExtraWait - (now - started)
            if limit <= 0 { return .timedOut }
            try? await Task.sleep(for: .seconds(min(0.025, remaining, limit)))
        }
        return .unavailable // The caller checks cancellation before issuing a recorder action.
    }

    private func observe(type: NSEvent.EventType, location: CGPoint, time: TimeInterval) {
        guard state != nil else { return }
        if [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged].contains(type) {
            let dx = location.x - pointer.x, dy = location.y - pointer.y
            guard dx * dx + dy * dy >= 16 else { return }
            pointer = location
        }
        state?.observe(at: time, keyboard: [.keyDown, .keyUp, .flagsChanged].contains(type))
    }
}
