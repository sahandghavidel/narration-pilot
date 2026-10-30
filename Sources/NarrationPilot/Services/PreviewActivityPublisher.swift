import AppKit
import Foundation

/// Low-frequency activity messages contain no narration or clipboard contents.
@MainActor
final class PreviewActivityPublisher {
    private var speaking = false
    private var recording = false
    private var checkedAt: TimeInterval = 0
    private var queryInFlight = false
    private var timer: Timer?
    private var requestObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private let queue = DispatchQueue(label: "local.clipboardreadermac.preview-recording-state", qos: .utility)

    func start() {
        guard timer == nil else { return }
        requestObserver = DistributedNotificationCenter.default().addObserver(
            forName: .init("local.clipboardreadermac.preview-activity.request"), object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.publish() } }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in
            self?.speaking = false; self?.recording = false; self?.publish()
        } }
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = 0.2
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        tick()
    }

    func update(speaking: Bool) { self.speaking = speaking; publish() }

    private func tick() {
        publish()
        guard !queryInFlight else { return }
        if NSRunningApplication.runningApplications(withBundleIdentifier: FocuSeeAccessibilityService.bundleIdentifier).isEmpty {
            recording = false; checkedAt = ProcessInfo.processInfo.systemUptime
            return
        }
        guard ProcessInfo.processInfo.systemUptime - checkedAt >= 2 else { return }
        queryInFlight = true
        let started = ProcessInfo.processInfo.systemUptime
        queue.async { [weak self] in
            let state = FocuSeeAccessibilityService().recordingState()
            Task { @MainActor [weak self] in
                guard let self else { return }
                queryInFlight = false
                recording = state == .recording && ProcessInfo.processInfo.systemUptime - started < 1.5
                checkedAt = ProcessInfo.processInfo.systemUptime
                publish()
            }
        }
    }

    private func publish() {
        let now = ProcessInfo.processInfo.systemUptime
        DistributedNotificationCenter.default().postNotificationName(
            .init("local.clipboardreadermac.preview-activity.v1"), object: "local.clipboardreadermac",
            userInfo: ["version": 1, "pid": ProcessInfo.processInfo.processIdentifier,
                       "speaking": speaking, "recording": recording && now - checkedAt < 3,
                       "sentAt": now], deliverImmediately: true)
    }
}
