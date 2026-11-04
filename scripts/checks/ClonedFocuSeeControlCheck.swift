import Foundation

@main
struct ClonedFocuSeeControlCheck {
    @MainActor static func main() async {
        let controller = ClonedFocuSeeControl()
        var commands = 0
        var probes = 0
        var events: [String] = []
        controller.trigger = { commands += 1; return true }
        controller.event = { events.append($0) }
        controller.sample = {
            probes += 1
            return probes == 1 ? .paused : .recording
        }
        let start = ProcessInfo.processInfo.systemUptime
        let error = await controller.ensure(.recording)
        precondition(error == nil && commands == 1 && probes == 2)
        precondition(ProcessInfo.processInfo.systemUptime - start < 0.3, "No fixed 500ms wait should remain")
        precondition(events == ["focusee.recording.checkStarted", "focusee.recording.commandSent", "focusee.recording.confirmed"])
        controller.sample = { .paused }; commands = 0
        let alreadyPaused = await controller.ensure(.paused)
        precondition(alreadyPaused == nil && commands == 0)
        controller.sample = { .unknown }
        let unknown = await controller.ensure(.recording)
        precondition(unknown != nil && commands == 0)
        controller.sample = { .notRunning }
        let closed = await controller.ensure(.recording)
        precondition(closed != nil && commands == 0)
        controller.sample = { .paused }; controller.timeout = 0.04
        let timedOut = await controller.ensure(.recording)
        precondition(timedOut != nil && commands == 1, "An unconfirmed transition must never send another toggle")
        commands = 0; controller.timeout = 2
        let pending = Task { await controller.ensure(.recording) }
        try? await Task.sleep(for: .milliseconds(20))
        pending.cancel()
        let cancelled = await pending.value
        precondition(cancelled != nil && commands == 1)
        commands = 0; controller.trigger = { false }
        let triggerFailed = await controller.ensure(.recording)
        precondition(triggerFailed != nil && commands == 0)
        print("PASS: immediate state confirmation without fixed sleep, already-target no-op, unknown/closed fail-closed, one-toggle timeout, cancellation and trigger failure; no FocuSee actions sent")
    }
}
