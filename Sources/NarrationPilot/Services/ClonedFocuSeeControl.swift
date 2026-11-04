import AppKit
import ApplicationServices
import Foundation

/// Cloned-audio-only state confirmation. A command is sent once, only from a
/// freshly observed opposite state; polling never retries a toggle.
@MainActor
final class ClonedFocuSeeControl {
    var sample: () async -> FocuSeeRecordingState
    var trigger: () -> Bool = { false }
    var event: (String) -> Void = { _ in }
    var timeout: TimeInterval = 2
    private let probe: FastFocuSeeProbe
    private let queue = DispatchQueue(label: "narration-pilot.cloned-focusee-probe", qos: .userInitiated)

    init() {
        let probe = FastFocuSeeProbe()
        self.probe = probe
        let queue = self.queue
        sample = {
            await withCheckedContinuation { continuation in
                queue.async { continuation.resume(returning: probe.state()) }
            }
        }
    }

    /// Read-only warm-up before the user starts a take; also records which build
    /// and process observed the state for support without sending a shortcut.
    func prime() async {
        let began = ProcessInfo.processInfo.systemUptime
        let observed = await sample()
        let payload: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier,
            "observedState": String(describing: observed), "readOnly": true,
            "probeMilliseconds": (ProcessInfo.processInfo.systemUptime - began) * 1000,
            "updatedAt": ISO8601DateFormatter().string(from: Date())]
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/local.clipboardreadermac/Runtime/cloned-focusee-state.json")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: .sortedKeys) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func ensure(_ target: FocuSeeRecordingState) async -> String? {
        guard target == .recording || target == .paused else { return "Unsupported recorder state." }
        let name = target == .recording ? "recording" : "paused"
        event("focusee.\(name).checkStarted")
        let initial = await sample()
        guard !Task.isCancelled else { return "Recorder action cancelled." }
        if initial == target { event("focusee.\(name).confirmedAlready"); return nil }
        let opposite: FocuSeeRecordingState = target == .recording ? .paused : .recording
        guard initial == opposite else {
            return initial == .notRunning ? "FocuSee is not open."
                : "FocuSee does not have a confirmed active recording state. No toggle was sent."
        }
        guard trigger() else { return "Could not send the FocuSee shortcut." }
        event("focusee.\(name).commandSent")
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while !Task.isCancelled {
            let observed = await sample()
            guard !Task.isCancelled else { return "Recorder action cancelled." }
            if observed == target { event("focusee.\(name).confirmed"); return nil }
            if ProcessInfo.processInfo.systemUptime >= deadline { break }
            do { try await Task.sleep(for: .milliseconds(15)) }
            catch { return "Recorder action cancelled." }
        }
        return Task.isCancelled ? "Recorder action cancelled." : "FocuSee did not confirm \(name). No second toggle was sent."
    }
}

/// Used exclusively on ClonedFocuSeeControl's serial queue. Cached controls are
/// freshly read each time and discarded on PID/window changes or invalid AX data.
private final class FastFocuSeeProbe: @unchecked Sendable {
    private var pid: pid_t?
    private var windows: [AXUIElement] = []
    private var controls: [(AXUIElement, AXUIElement)] = [] // control, owning window

    func state() -> FocuSeeRecordingState {
        let fast = fastState()
        // Preserve the proven detector's coverage for FocuSee versions exposing
        // floating recorder controls outside the fast roots. This is still a
        // fresh read; it never assumes paused/recording or retries a toggle.
        if fast == .unknown || fast == .notRecording {
            return FocuSeeAccessibilityService().recordingState()
        }
        return fast
    }

    private func fastState() -> FocuSeeRecordingState {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: FocuSeeAccessibilityService.bundleIdentifier).first else {
            clear(); return .notRunning
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.05)
        let allWindows = value(kAXWindowsAttribute, root) as? [AXUIElement] ?? []
        // Editor playback controls must not be mistaken for recording controls.
        let freshWindows = allWindows.filter { (value(kAXTitleAttribute, $0) as? String)?.lowercased() != "edit" }
        var roots = freshWindows
        // FocuSee's floating recorder can be an application-level accessibility
        // child that is absent from AXWindows (e.g. its picker/system-dialog UI).
        // The older detector traversed this path; keep that coverage here.
        if let children = value(kAXChildrenAttribute, root) as? [AXUIElement] {
            for child in children {
                let role = value(kAXRoleAttribute, child) as? String
                guard role != kAXMenuBarRole as String,
                      (value(kAXTitleAttribute, child) as? String)?.lowercased() != "edit",
                      !CFEqual(child, root), !roots.contains(where: { CFEqual($0, child) }) else { continue }
                roots.append(child)
            }
        }
        if let menuValue = value(kAXMenuBarAttribute, root), CFGetTypeID(menuValue) == AXUIElementGetTypeID() {
            let menu = unsafeDowncast(menuValue, to: AXUIElement.self)
            if let children = value(kAXChildrenAttribute, menu) as? [AXUIElement] {
                roots += children.filter { (value(kAXTitleAttribute, $0) as? String)?.lowercased() == "record" }
            }
        }
        let sameWindows = pid == app.processIdentifier && roots.count == windows.count
            && roots.allSatisfy { window in windows.contains { CFEqual($0, window) } }
        if !sameWindows { controls = [] }
        pid = app.processIdentifier; windows = roots
        if !controls.isEmpty {
            var fresh: [FocuSeeAccessibilityElementSnapshot] = []
            for (control, window) in controls {
                guard roots.contains(where: { CFEqual($0, window) }), belongs(control, to: window),
                      let snapshot = snapshot(control), isStateControl(snapshot) else {
                    controls = []; fresh = []; break
                }
                fresh.append(snapshot)
            }
            if !fresh.isEmpty { return FocuSeeAccessibilityService.classify(isRunning: true, elements: fresh) }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.6
        var queue = roots.map { ($0, $0, 0) }
        var index = 0
        var visited: [AXUIElement] = []
        var discovered: [(AXUIElement, AXUIElement)] = []
        var snapshots: [FocuSeeAccessibilityElementSnapshot] = []
        while index < queue.count {
            guard index < 600, ProcessInfo.processInfo.systemUptime < deadline else { controls = []; return .unknown }
            let (element, window, depth) = queue[index]; index += 1
            if visited.contains(where: { CFEqual($0, element) }) { continue }
            visited.append(element)
            if let snapshot = snapshot(element), isStateControl(snapshot) {
                discovered.append((element, window)); snapshots.append(snapshot)
            }
            if depth < 12, let children = value(kAXChildrenAttribute, element) as? [AXUIElement] {
                queue.append(contentsOf: children.map { ($0, window, depth + 1) })
            }
        }
        controls = discovered
        return snapshots.isEmpty ? (freshWindows.isEmpty ? .notRecording : .unknown)
            : FocuSeeAccessibilityService.classify(isRunning: true, elements: snapshots)
    }

    private func belongs(_ control: AXUIElement, to root: AXUIElement) -> Bool {
        if value(kAXRoleAttribute, root) as? String == kAXWindowRole as String {
            if let window = value(kAXWindowAttribute, control) { return CFEqual(window, root) }
        }
        var element = control
        for _ in 0..<14 {
            if CFEqual(element, root) { return true }
            guard let parent = value(kAXParentAttribute, element), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return false }
            element = unsafeDowncast(parent, to: AXUIElement.self)
        }
        return false
    }

    private func snapshot(_ element: AXUIElement) -> FocuSeeAccessibilityElementSnapshot? {
        guard let role = value(kAXRoleAttribute, element) as? String,
              role == kAXButtonRole as String || role == kAXMenuItemRole as String || role == kAXStaticTextRole as String,
              (role == kAXMenuItemRole as String || (value("AXHidden", element) as? Bool) != true) else { return nil }
        guard role == kAXStaticTextRole as String || (value(kAXEnabledAttribute, element) as? Bool) == true else { return nil }
        let labels = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXValueAttribute, kAXIdentifierAttribute]
            .compactMap { value($0, element) as? String }
        return .init(role: role, labels: labels, isEnabled: true)
    }

    private func isStateControl(_ snapshot: FocuSeeAccessibilityElementSnapshot) -> Bool {
        snapshot.labels.contains { label in
            let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if snapshot.role == kAXStaticTextRole as String { return ["rec", "recording", "paused"].contains(normalized) }
            return ["pause", "pause recording", "resume", "resume recording", "continue recording"].contains(normalized)
        }
    }

    private func value(_ attribute: String, _ element: AXUIElement) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, 0.05)
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
    }
    private func clear() { pid = nil; windows = []; controls = [] }
}
