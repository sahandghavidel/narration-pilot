import AppKit
import ApplicationServices
import Darwin
import Foundation

/// A kernel-held lock survives neither exit nor crash, so stale PID files
/// cannot prevent the next login. The lock file itself must never be unlinked.
final class RuntimeProcessLease {
    private var descriptor: Int32 = -1
    func acquire(at url: URL) -> Bool {
        guard descriptor == -1 else { return true }
        let fd = Darwin.open(url.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { return false }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { Darwin.close(fd); return false }
        descriptor = fd
        return true
    }
    deinit { if descriptor >= 0 { Darwin.close(descriptor) } }
}

@MainActor
final class RuntimeReliability {
    static let shared = RuntimeReliability()
    private let lease = RuntimeProcessLease()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var recovery: (() -> Void)?
    private var resume: (() -> Void)?
    private var snapshot: (() -> [String: Bool])?
    private var lastTrusted = false
    private var lastSnapshot: [String: Bool] = [:]
    private var lastWrite: TimeInterval = 0
    private var directory: URL?

    func prepare(name: String, identifier: String) -> Bool {
        let canonical = URL(fileURLWithPath: "/Applications/\(name).app")
        let running = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        if running.pathExtension == "app", running != canonical,
           Bundle(url: canonical)?.bundleIdentifier == identifier {
            // A stale login/Dock/build-folder reference opens the installed app.
            NSWorkspace.shared.open(canonical)
            return false
        }
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true)
            let dir = support.appendingPathComponent(identifier).appendingPathComponent("Runtime")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            directory = dir
            return lease.acquire(at: dir.appendingPathComponent("instance.lock"))
        } catch {
            fputs("Unable to establish application instance lock: \(error.localizedDescription)\n", stderr)
            return false
        }
    }

    func start(recover: @escaping () -> Void, resume: (() -> Void)? = nil, listeners: @escaping () -> [String: Bool]) {
        guard timer == nil else { return }
        recovery = recover; self.resume = resume; snapshot = listeners; lastTrusted = AXIsProcessTrusted()
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.recoverAfterWake() }
            })
        }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.check() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        writeStatus(reason: "launched")
    }

    private func recoverAfterWake() {
        (resume ?? recovery)?()
        writeStatus(reason: "session-resumed")
        // Login/window-server startup and permission grants can settle later.
        for delay in [1.0, 4.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.check() }
        }
    }

    private func check() {
        let trusted = AXIsProcessTrusted()
        let states = snapshot?() ?? [:]
        if trusted && (!lastTrusted || states.values.contains(false)) { recovery?() }
        let now = ProcessInfo.processInfo.systemUptime
        if trusted != lastTrusted || states != lastSnapshot || now - lastWrite >= 30 {
            writeStatus(reason: "health-check")
        }
        lastTrusted = trusted
    }

    func stop() {
        timer?.invalidate(); timer = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        writeStatus(reason: "terminated")
        recovery = nil; resume = nil; snapshot = nil
    }

    private func writeStatus(reason: String) {
        guard let directory else { return }
        lastSnapshot = snapshot?() ?? [:]
        lastWrite = ProcessInfo.processInfo.systemUptime
        let data: [String: Any] = ["reason": reason, "pid": ProcessInfo.processInfo.processIdentifier,
            "path": Bundle.main.bundlePath, "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "revision": Bundle.main.object(forInfoDictionaryKey: "BuildRevision") as? String ?? "unknown",
            "builtAt": Bundle.main.object(forInfoDictionaryKey: "BuildDateUTC") as? String ?? "unknown",
            "accessibilityTrusted": AXIsProcessTrusted(), "listeners": lastSnapshot,
            "updatedAt": ISO8601DateFormatter().string(from: Date())]
        do {
            let url = directory.appendingPathComponent("status.json")
            try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { /* Diagnostics must not disrupt application operation. */ }
    }
}
