import Foundation

/// Watches the directory because producers publish commands by atomic rename.
@MainActor
final class GuidedCommandInbox {
    private var source: DispatchSourceFileSystemObject?

    func watch(_ directory: URL, changed: @escaping @MainActor () -> Void) {
        guard source == nil else { return }
        let fd = open(directory.path, O_EVTONLY | O_CLOEXEC)
        guard fd >= 0 else { changed(); return }
        let watcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename, .revoke], queue: .main
        )
        source = watcher
        watcher.setCancelHandler { close(fd) }
        watcher.setRegistrationHandler { changed() } // Recover commands already present at launch.
        watcher.setEventHandler { [weak self] in
            guard let self, let current = self.source, !current.isCancelled else { return }
            if !current.data.intersection([.delete, .rename, .revoke]).isEmpty {
                self.stop() // The heartbeat reattaches to the replacement directory.
            }
            changed()
        }
        watcher.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    static func pendingFiles(in directory: URL) -> [URL] {
        let commands = directory.appendingPathComponent("commands")
        let fm = FileManager.default
        // Read receipts first: a concurrently arriving command must remain visible.
        let receipts = Set((try? fm.contentsOfDirectory(atPath: directory.appendingPathComponent("receipts").path)) ?? [])
        return ((try? fm.contentsOfDirectory(atPath: commands.path)) ?? []).compactMap { name in
            guard name.hasSuffix(".json"), !receipts.contains(name) else { return nil }
            return commands.appendingPathComponent(name)
        }
    }
}
