import Foundation
@main struct LeaseCheck {
    static func main() throws {
        if CommandLine.arguments.count == 3 {
            let lease = RuntimeProcessLease()
            precondition(lease.acquire(at: URL(fileURLWithPath: CommandLine.arguments[2])))
            FileHandle.standardOutput.write(Data("ready\n".utf8))
            Thread.sleep(forTimeInterval: 10)
            return
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lease-check-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("app.lock")
        let child = Process(), pipe = Pipe()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["hold",url.path]; child.standardOutput = pipe
        try child.run()
        _ = try pipe.fileHandleForReading.read(upToCount: 6)
        let blocked = RuntimeProcessLease()
        precondition(!blocked.acquire(at: url))
        let separate = RuntimeProcessLease()
        precondition(separate.acquire(at: dir.appendingPathComponent("other-app.lock")))
        child.terminate(); child.waitUntilExit()
        precondition(blocked.acquire(at: url)) // stale file after crash never blocks
        let link = dir.appendingPathComponent("link.lock")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        precondition(!RuntimeProcessLease().acquire(at: link))
        print("Process lock checks passed: duplicate exclusion, independent apps, crash recovery, symlink rejection")
    }
}
