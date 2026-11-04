import Foundation

@main
struct GuidedNarrationReviewCheck {
    @MainActor static func main() async throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--bridge" {
            let bridge = GuidedNarrationReview(directory: URL(fileURLWithPath: CommandLine.arguments[2]))
            bridge.canSpeak = { nil }
            bridge.speak = { _, token in bridge.speechFinished(token) }
            bridge.start()
            for _ in 0..<600 {
                await bridge.processInbox()
                if bridge.phase == "awaitingDecision" {
                    if bridge.draft?.revision == 1 { bridge.improve() } else { bridge.approve() }
                }
                if !bridge.active && bridge.draft != nil { bridge.stop(); return }
                try await Task.sleep(for: .milliseconds(50))
            }
            bridge.stop(); throw NSError(domain: "BridgeCheck", code: 1)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("guided-review-check-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let review = GuidedNarrationReview(directory: root)
        review.canSpeak = { nil }
        var spoken: [(String, UUID)] = []
        review.speak = { spoken.append(($0, $1)) }
        func receipt(_ id: UUID) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("receipts/\(id.uuidString).json"))) as! [String: Any]
        }
        func queue(_ command: GuidedNarrationCommand) throws {
            try GuidedNarrationReview.encoder().encode(command).write(to: root.appendingPathComponent("commands/\(command.id.uuidString).json"), options: .atomic)
        }
        func send(_ command: GuidedNarrationCommand, accepted: Bool = true) async throws {
            try queue(command); await review.processInbox()
            let result = try receipt(command.id)
            precondition(result["accepted"] as? Bool == accepted, result.description)
        }
        func command(_ kind: String, _ draft: GuidedNarrationDraft, event: UUID? = nil) -> GuidedNarrationCommand {
            GuidedNarrationCommand(id: UUID(), sessionID: draft.sessionID, kind: kind, draft: kind == "submit" ? draft : nil, eventID: event)
        }
        precondition(!review.approve() && !review.improve(), "Inactive review must leave audio actions available")
        let first = GuidedNarrationDraft(sessionID: UUID(), sceneID: "test-scene", revision: 1, narration: "Let's add twelve and eight.")
        let initial = command("submit", first)
        try await send(initial)
        precondition(review.active && review.phase == "reading" && spoken.count == 1)
        precondition(spoken[0].0.contains(first.narration))
        let oldToken = spoken[0].1
        precondition(review.approve())
        let approved = review.decision!
        precondition(approved.kind == "approveNarration" && approved.draft == first)
        precondition(review.phase == "approved")
        _ = review.approve(); _ = review.improve()
        precondition(review.decision?.id == approved.id)
        review.speechFinished(oldToken)
        precondition(review.phase == "approved", "An old completion cannot reopen the decision gate")
        try await send(command("acknowledge", first, event: UUID()), accepted: false)
        precondition(!review.acknowledged)
        let ack = command("acknowledge", first, event: approved.id)
        try await send(ack); precondition(review.acknowledged)
        try await send(ack) // Same command ID is a durable no-op.
        var forbidden = first; forbidden.revision = 2; forbidden.narration = "Changed after approval."
        try await send(command("submit", forbidden, event: approved.id), accepted: false)
        let restoredApproval = GuidedNarrationReview(directory: root)
        precondition(restoredApproval.active && restoredApproval.phase == "approved" && restoredApproval.acknowledged)
        precondition(restoredApproval.decision?.id == approved.id && restoredApproval.decision?.draft == approved.draft)
        try await send(command("end", first))
        precondition(!review.active && !review.approve() && !review.improve())

        let second = GuidedNarrationDraft(sessionID: UUID(), sceneID: "test-scene", revision: 1, narration: "The result is twenty.")
        try await send(command("submit", second))
        let readingToken = spoken.last!.1
        review.speechFinished(readingToken)
        precondition(review.phase == "awaitingDecision")
        precondition(review.improve()); let improvement = review.decision!
        precondition(improvement.kind == "improveNarration")
        _ = review.approve(); precondition(review.decision == improvement)
        try await send(command("acknowledge", second, event: improvement.id))
        var revised = second; revised.revision = 2; revised.narration = "Click equals. The result is twenty."
        try await send(command("submit", revised, event: UUID()), accepted: false)
        var skipped = revised; skipped.revision = 3
        try await send(command("submit", skipped, event: improvement.id), accepted: false)
        let replacement = command("submit", revised, event: improvement.id)
        try await send(replacement)
        precondition(review.draft == revised && review.decision == nil && review.phase == "reading")
        let speechCount = spoken.count
        try await send(replacement)
        try await send(command("submit", revised, event: improvement.id))
        precondition(spoken.count == speechCount, "Duplicate commands/drafts must not repeat speech")
        review.speechFinished(readingToken); precondition(review.phase == "reading")
        try await send(command("acknowledge", second, event: improvement.id), accepted: false)
        let restoredReading = GuidedNarrationReview(directory: root)
        precondition(restoredReading.phase == "suspended" && restoredReading.active && restoredReading.decision == nil)
        _ = review.approve(); let approvedRevision = review.decision!
        precondition(approvedRevision.draft == revised && approvedRevision.id != improvement.id)
        let eventFiles = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("events"), includingPropertiesForKeys: nil)
        precondition(eventFiles.count == 3, "One immutable decision per revision")
        precondition(eventFiles.contains { (try? GuidedNarrationReview.decoder().decode(GuidedNarrationDecision.self, from: Data(contentsOf: $0)))?.id == improvement.id })
        try await send(command("end", revised))

        let blocked = GuidedNarrationDraft(sessionID: UUID(), sceneID: "blocked", revision: 1, narration: "Pause before previewing.")
        review.canSpeak = { "FocuSee is recording" }
        let beforeBlocked = spoken.count
        try await send(command("submit", blocked))
        precondition(review.phase == "blocked" && spoken.count == beforeBlocked)
        _ = review.approve(); _ = review.improve(); precondition(review.decision == nil)
        review.canSpeak = { nil }
        await review.replay(); precondition(review.phase == "reading")
        review.interruptSpeech(); precondition(review.phase == "suspended")
        _ = review.approve(); precondition(review.decision == nil)
        await review.replay(); review.speechFailed(spoken.last!.1)
        precondition(review.phase == "blocked")
        try await send(command("end", blocked))

        // A permission/state lookup completing after End cannot begin speech.
        let late = GuidedNarrationDraft(sessionID: UUID(), sceneID: "late", revision: 1, narration: "Do not speak after ending.")
        var continuation: CheckedContinuation<String?, Never>?
        review.canSpeak = { await withCheckedContinuation { continuation = $0 } }
        let lateCommand = command("submit", late); try queue(lateCommand)
        let processing = Task { await review.processInbox() }
        for _ in 0..<100 { if continuation != nil { break }; await Task.yield() }
        precondition(continuation != nil && review.phase == "checking")
        _ = review.approve(); precondition(review.decision == nil)
        review.end(); let count = spoken.count; continuation?.resume(returning: nil)
        await processing.value
        precondition(!review.active && spoken.count == count)
        var invalid = late; invalid.sessionID = UUID(); invalid.narration = "  "
        try await send(command("submit", invalid), accepted: false)
        review.stop()
        print("PASS: narration approval/improvement handshake, exact revision events, durable acknowledgments, shortcut ownership, duplicate suppression, restart recovery, blocked/interrupted speech and stale completion guards; no real speech or recording")
    }
}
