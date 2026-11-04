# Agent feedback

Expand **Agent Feedback** in the menu bar panel to enable local feedback, copy the current snapshot, configure **Copy Current Scene for Agent**, or open the feedback folder. The copy shortcut has no default binding, preserving existing shortcuts. Copy works without enabling continuous publication.

Live file: `~/Library/Application Support/local.clipboardreadermac/AgentFeedback/status.json`.

The snapshot contains loaded scene content (including code/prompt/command fields), script/chapter context, current speech passage/word, elapsed speaking time, separately labelled estimated scene duration, observed FocuSee state, and an active take with a frozen starting scene. It includes up to 20 recent takes and 100 transition events for the current app session. Unsaved editor drafts are not the loaded playback scene. Existing configured actions and recording behavior are unchanged.

Consumers must reject snapshots when `appRunning` is false or `updatedAt` is more than `staleAfterSeconds` old. FocuSee `observedState` is independently sampled through accessibility about once per second and becomes `unknown` if unavailable or stale. Requested stages are not capture confirmation. `pauseConfirmed` means the existing FocuSee state check succeeded after narration; it does not verify saved footage. `narrationCompleted` does not imply capture. Check `requiresReview` and `issues` on completed takes. No recorder project/file ID is claimed: take IDs belong to Narration Pilot.

No service, network endpoint, Baserow writes, credentials, or automatic clipboard access is added. Feedback files are atomically replaced with mode 0600 in a mode 0700 directory. Disabling publication removes the live file. Publishing is off by default. Narration and instructions can contain sensitive text; they are only written locally when enabled or copied explicitly.

Focused check (does not play speech, alter app preferences, or control FocuSee):

```sh
swiftc -swift-version 6 -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk Sources/NarrationPilot/Services/AgentFeedbackPublisher.swift Sources/NarrationPilot/Services/FocuSeeAccessibilityService.swift scripts/checks/AgentFeedbackCheck.swift -o /tmp/narration-agent-feedback-check
/tmp/narration-agent-feedback-check
```

Live acceptance: rehearse a selected scene, trigger the existing recording-and-read shortcut, verify observed recording and speech progress, then verify narration completion, observed pause, and matching take scene ID after scene advancement. Review footage in FocuSee. Unknown recording state must never be treated as confirmation.
