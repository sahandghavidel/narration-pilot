<div align="center">

# Narration Pilot

**A scene-by-scene narration companion for macOS.**

[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-111827?logo=apple)](https://www.apple.com/macos/)
[![Swift 6.3](https://img.shields.io/badge/Swift-6.3-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![MIT License](https://img.shields.io/badge/License-MIT-22C55E.svg)](LICENSE)
[![Local first](https://img.shields.io/badge/Privacy-Local--first-38BDF8)](#privacy)

![Narration Pilot — scene-by-scene narration for macOS](docs/images/narration-pilot-hero.svg)

</div>

Narration Pilot is a native macOS menu bar app for tutorial creators, screen recorders, and anyone who needs reliable text-to-speech while working through a script. Paste or type a script, organize it into scenes, play one scene at a time, and control the entire session with global shortcuts.

## Why Narration Pilot?

Traditional text-to-speech tools read a whole document. Narration Pilot treats a script as a production workflow: the current scene stays in focus, recording directions can remain visible without being narrated, and external shortcuts can start or stop another recording app around speech.

## Features

| Area | What Narration Pilot provides |
| --- | --- |
| **Scene playback** | Text scripts with automatic sentence splitting or structured chapter JSON with explicit scenes |
| **Scene Manager** | Select, edit, split, merge, and delete scenes while preserving manual scene boundaries |
| **Production directions** | Normal playback skips text inside square brackets; Replay Scene includes it |
| **Presenter overlay** | Previous, current, and next scene context with adjustable placement, size, opacity, typography, and colors |
| **Recording-friendly UI** | Presenter overlay and Scene Manager can be hidden from standard macOS screen capture |
| **Global shortcuts** | Two current-input shortcuts and three always-read-clipboard shortcuts, each with its own speech speed |
| **Recording automation** | Verified FocuSee actions, independent delays, optional cue sounds, and Neon Spotlight fade-out waiting |
| **Speech controls** | macOS voices, adjustable rate, pause, resume, stop, and replay |
| **Cloned clipboard audio** | Generate, save, and preview individual clipboard passages using Ultimate Video Editor English voice presets; retain earlier versions |
| **Input choices** | Read the clipboard, entered text, or a scene-based script |
| **Privacy** | Local-first operation with no analytics, accounts, advertising, or project-owned cloud storage |

## How it works

1. Paste a tutorial script or enter text directly.
2. Turn on **Script mode** to create sentence-based scenes.
3. Use **Play Scene** or a global shortcut to narrate the current scene.
4. Narration Pilot advances to the next scene when speech finishes.

For example:

```text
[On screen: Open the image overlay window.] Yesterday, I wanted to add a new option here.
```

Normal playback reads only the narration. **Replay Scene** reads the complete scene, including the bracketed direction.

## Requirements

- macOS 15 or newer
- Apple Silicon Mac—the currently tested architecture
- Xcode and the Xcode Command Line Tools when building from source

## Quick start

Clone and build the project:

```bash
git clone https://github.com/sahandghavidel/narration-pilot.git
cd narration-pilot
swift build
```

Run the newest debug build:

```bash
./scripts/dev-run.sh
```

Run an optimized release build without installing an app bundle:

```bash
./scripts/build-app.sh release
```

The signed test bundle is created at
`.build/app/release/Narration Pilot.app`. Use `dev-release-run.sh` only when you
want to run the raw SwiftPM executable instead of an application bundle.

## Install the macOS app locally

```bash
./scripts/install-local-app.sh
```

This installs `/Applications/Narration Pilot.app` and launches it. Upgrades retain the legacy `local.clipboardreadermac` bundle identifier so people upgrading from Clipboard Reader keep their shortcuts and settings.

> [!NOTE]
> The raw SwiftPM executable and the installed app use different macOS preferences domains. Use the installed app for normal work when you want one stable set of shortcuts and settings.

## Using Narration Pilot

### Reading modes

- Leave **Read typed text instead of clipboard** off to read the current clipboard.
- Turn it on to read text entered in the app.
- Turn on **Script mode** to split a tutorial script into scenes and play one scene at a time.

### Scene workflow

Use **Previous**, **Replay**, **Next**, and **Restart** to navigate. Open **Edit Current Scene** to select, edit, split, merge, or delete scenes. Manual boundaries remain in place until the raw script is changed directly.

### Chapter JSON mode

Turn on **Script mode**, select **Chapter JSON**, and import a version 5 chapter file. Each scene keeps `narration`, one `onScreen` recording instruction, optional structured `code`, an optional `postProduction` note, and an optional AI `annotation`. Speech and Replay read only `narration`; Replay On Screen Only reads the instruction separately. The JSON Scene Manager edits and safely saves these fields. Plain-text prompts and shell commands use a selectable, wrapping text preview with Edit Text/Copy Text or Edit Command/Copy Command controls; HTML, CSS, and JavaScript keep syntax highlighting. Narration Pilot remembers the active chapter after restarting, and changes detected during speech are applied when speech finishes. Versions 2–4 remain readable and are migrated in memory.

Narration Pilot can also receive a JSON file directly:

```bash
./scripts/open-chapter-json.sh /path/to/chapter.json
```

Validate a chapter without launching the app:

```bash
swiftc Sources/NarrationPilot/Models/NarrationChapter.swift scripts/validate-chapter-json.swift -o /tmp/validate-chapter-json
/tmp/validate-chapter-json /path/to/chapter.json
```

### Presenter overlay

The overlay shows the previous, current, and next scenes. It supports custom sizing, placement, opacity, typography, colors, and quick color presets. You can hide it from standard macOS screen capture or hide it automatically while speech is playing.

### Ultimate Video Editor voice selection

The **Ultimate Video Editor voice** section sits above **Speech settings** in the
menu bar panel. It loads enabled English OmniVoice and OmniVoice LoRA presets
from `http://localhost:9540/api/tts-audio-references`. Open Ultimate Video Editor
and click **Refresh** if the connection is unavailable. Your choice is saved
automatically and retained across restarts and connection failures.

This selection is used by the separate **Cloned Voice Audio** section. The existing
macOS voice selection under **Speech settings** continues to control all existing
speech shortcuts.

### Cloned clipboard audio

Copy one scene's narration and press **Command + Shift + T**, or click
**Prepare & Preview Clipboard** under **Cloned Voice Audio**. The shortcut can
be changed with its recorder in that section. It always reads the clipboard,
regardless of the script or typed-text input mode. Bracketed recording directions
are skipped, as with normal speech. If this narration and voice already have an
approved version, the shortcut previews that exact local WAV without regenerating
audio. If no approved version exists, it generates and saves a new version using
the selected English preset and its configured seed behavior. Saved word timings
are reused when present. Repeated presses while preparing
audio are ignored.

Choose a **Saved narration** and **Version** to replay older audio without regeneration, use **Stop
Preview** to stop only cloned audio, or **Show File** to reveal the WAV in Finder.
Versions and their original clipboard text, spoken text, voice, measured duration,
and generation response are retained across restarts under
`~/Library/Application Support/local.clipboardreadermac/ClonedClipboardAudio/`.
Each narration/voice pair gets one readable folder ending in a SHA-256 key.
Its `group.json` stores the approved version ID, and its `versions/<UUID>/`
folders contain `audio.wav` and `metadata.json`. Matching removes bracketed
directions and normalizes whitespace; case, punctuation, and wording remain
significant. Different voice preset IDs always have separate folders and approvals.

Click **Approve Selected Audio** after reviewing a version. Approval survives
restarts. **Generate New Version** explicitly generates from the current clipboard
and voice even if approval exists; it keeps the old approval until you approve a
replacement. Incomplete saves are not shown; failed generations preserve earlier
versions. A missing approved file reports an error instead of silently generating.

Approval also starts **Tiny.en** transcription in the background. The existing
editor endpoint `/api/transcribe-scene` is called with `model: "tiny"`. Each
version's `transcription.json` stores the recognized text, word start/end times,
model, actual WAV duration, creation time, and the audio's SHA-256 fingerprint.
Approval is saved before transcription; a transcription failure never regenerates
or unapproves audio. The panel shows **Transcribing**, **Timings ready**, or an
error with **Retry Transcription**. Existing approved versions without timings
offer **Create Word Timings**, and preparing approved audio also fills a missing
cache. Duplicate transcription requests for a version are ignored.

Matching, valid timings are reused across playback and restarts without any
network request. A changed WAV invalidates its timings. New versions have their
own independent caches. The editor's original MinIO audio must still be available
for first-time transcription or retry: the client verifies that it matches the
local WAV before asking the existing URL-based endpoint to transcribe it. It
also rechecks the local fingerprint before atomically saving the result. Missing
or mismatched source audio reports an error; saved playback remains available.

Ultimate Video Editor must be running at `http://localhost:9540` for new generation;
approved local audio can be reused while the editor is offline. Narration is
sent only when generation is requested, through its existing
`/api/generate-tts-selected` route; generated audio uses the editor's configured
MinIO storage before being downloaded locally. A `clipboard-<UUID>` scene label
satisfies the route's filename requirement and does not update Baserow rows.
Preset IDs select the existing reference and engine settings; this feature does
not change the editor or its presets.

Generation and preview require macOS speech to be idle and FocuSee to be paused,
stopped, or closed. Unknown recording state blocks preview. Preview is checked
again after generation and stops if speech or recording becomes active. No
recording shortcut is sent, no scene is advanced, and there is no fallback to
macOS speech. Approved audio recording has its own controls below.

Cloned audio has independent, configurable shortcut recorders for **Prepare &
Preview Clipboard** (Command–Shift–T), **Regenerate & Preview Clipboard**
(Command–Shift–G), and **Approve Previewed Clipboard Audio** (Command–Shift–A).
Existing saved bindings are retained. Regeneration always creates a new version
without changing the current approval. The approval shortcut requires the selected
version to have been previewed in this app session and to match the current
clipboard narration and selected voice; it is blocked during generation or an
approved-audio take. Repeating approval does nothing. Approval saves immediately
and starts cached word-timing creation in the background. The library's explicit
**Approve Selected Audio** button remains available. The separate recording
shortcut retains its saved binding (Sahand's Command–Shift–R). macOS speech
shortcuts are unchanged.

### Guided narration and cloned-audio review

The guided session has two distinct review stages with the same configurable
A/G shortcuts. Narration Pilot announces each stage through a separate instance
of the existing macOS speech engine. Existing macOS speech behavior, voice/speed
settings, and shortcuts are unchanged.

1. The agent submits a draft. **Review narration** reads it using macOS speech.
   Command–Shift–G requests improved wording from the active agent; a revision
   must answer that exact improvement event. Command–Shift–A approves the wording.
2. Wording approval automatically prepares and previews cloned audio by calling
   the existing Ultimate Video Editor client directly. No clipboard change,
   Command–Shift–T dispatch, or agent acknowledgment is required to start it.
   Wording and the selected English voice are frozen for this audio review.
   An existing approved match is reused locally; otherwise a new version is saved.
3. **Review cloned audio** announces the stage, then plays the saved WAV.
   Command–Shift–G stops that candidate and generates another version using the
   same wording/voice, keeping previous versions and approvals. Command–Shift–A
   approves the exact previewed version and creates a separate audio approval
   event. Tiny.en word timings fill in the background; they do not delay approval.

A/G presses during generation, spoken stage transitions, or locked decisions are
consumed without approving a later stage or falling through to standalone audio
commands. A candidate must actually start previewing before it becomes approvable.
Changing clipboard text or library selection cannot change the approved guided
wording or candidate. If the selected candidate was not the last audio previewed,
replay the guided audio before approving it. No recording starts automatically.

Wording review requires other app-owned speech/audio/recording to be idle but is
independent of FocuSee's AX detector. Cloned-audio generation/preview retains the
existing recorder-state and speech-idle checks. Failure keeps wording and previous
audio approvals; use redo to retry. **Replay Saved Audio** replays a saved
candidate without generation. Ending a session cancels its work and prevents a
late response from starting playback. Restart restores saved state, never starts
speech/network/playback automatically, and requires a replay or explicit redo.

The panel shows narration revision, stage, frozen voice, candidate duration,
approval status, replay and **End Guided Review**. Outside a guided session, the
existing T/G/A/R audio shortcuts retain their standalone behavior. Existing
wording-only approvals can continue through redo or **Generate Audio**.

The private local bridge remains under
`~/Library/Application Support/local.clipboardreadermac/GuidedNarrationReview/`:
`commands/`, `receipts/`, narration `events/`, final `audio-events/`,
`acknowledgments/`, and live `status.json`. Audio events contain the exact wording,
voice, local audio version ID, duration, and generation attempt. Both kinds of
approval are independently acknowledged. Commands expire after two minutes;
decisions persist. This active-session bridge does not wake an ended chat.

```sh
python3 scripts/guided-narration-review.py submit --scene-id calculator-test --text "Let's add twelve and eight."
python3 scripts/guided-narration-review.py watch --session-id SESSION_UUID --revision 1 --ack --timeout 55
# An improvement event can be answered with a new wording revision:
python3 scripts/guided-narration-review.py submit --session-id SESSION_UUID --scene-id calculator-test --revision 2 --event-id IMPROVEMENT_EVENT_UUID --text "Click equals. The result is twenty."
# Wording approval is intermediate; keep the session open through audio approval:
python3 scripts/guided-narration-review.py watch --session-id SESSION_UUID --revision 2 --stage audio --ack --timeout 55
python3 scripts/guided-narration-review.py end --session-id SESSION_UUID
```

`submit` returns a receipt/session ID. A waiting result is not approval. Use
`status`, `replay`, or `generate-audio` to resume a saved session explicitly.

### Approved audio recording

Under **Approved Audio Recording**, assign the separate **Shortcut** recorder or
click **Record Approved Clipboard Audio**. The shortcut starts unassigned to avoid
replacing an existing binding. Copy narration with approved audio for the English
voice selected above. The approved version is matched by narration and voice,
even if a different candidate is currently selected in the audio library.

The WAV is loaded and prepared before any recorder action. Missing approval,
unreadable audio, or active macOS speech prevents the take. No generation,
transcription, scene navigation, or speech synthesis is performed during this
operation. Original WAV speed is fixed at 1.00x.

Cloned recording decodes the approved WAV to PCM before any recorder action and
prepares an output-only AVAudioEngine/AVAudioPlayerNode. The output graph stays
warm between takes and pauses after 30 seconds of inactivity; no audio is played
during warm-up. Playback progress comes from the node's sample timeline, and the
finishing action uses its `dataPlayedBack` completion, never an early rendered/
consumed callback or guessed duration subtraction. Stopping invalidates pending
callbacks, and an audio-engine interruption fails the take safely. macOS speech
and library preview continue using their original engines.

The settings mirror the existing clipboard speech shortcuts: **Before playback**,
**After playback**, independent 0–10 second delays, optional **Wait for Neon
Spotlight**, and **Wait until mouse and keyboard are idle**. Defaults are verified
FocuSee recording before playback, verified pause afterward, zero extra delays,
Neon waiting off, and input-idle waiting on. Cloned takes have visible, independent
**Mouse/activity quiet period** and **Keyboard quiet period** settings, both one
second by default, plus **Maximum extra idle wait** (10 seconds by default).
Existing settings migrate without resetting recorder actions or delays.

Enable **Fast mode** in Approved Audio Recording to use a single paused-state
precheck. It requires FocuSee to be paused in an active recording session, sends
Resume and immediately starts the prepared WAV without confirmation polling,
then sends Pause after actual playback completion and the enabled Neon/input
waits. Fast mode skips the before/after actions and explicit delays; their saved
values are preserved for use when Fast mode is off. Leave FocuSee's recording
state unchanged manually during a fast take, since the final toggle is not
verified. Completion reports that the pause command was sent rather than claiming
a confirmed paused state. Cancellation and failure retain verified-pause cleanup;
macOS speech takeover still avoids sending a late pause into the speech workflow.
Fast mode is off by default and persists independently of macOS speech settings.

Activity monitoring starts before WAV playback and continues through any finishing
delay or Neon wait. Inactivity already accumulated during playback counts: if the
last second of the WAV is quiet, the player completion event does not start a new
one-second wait. Otherwise the take waits only for the remaining quiet time, or
until its maximum extra wait is reached. Mouse, clicks, scrolling, and keyboard
activity in both Narration Pilot and other apps are observed without storing keys
or text. Small pointer jitter is ignored. Monitoring failures stop the take safely.
The cloned take no longer uses the macOS speech path's hardcoded keyboard wait;
that existing speech workflow remains unchanged.

Waits apply only when the after action is **Ensure FocuSee is paused**. The order
remains audio completion, explicit after delay, Neon wait, idle check using the
already running monitor, then the after action. Zero after delay and an already
idle monitor allow an immediate pause request at WAV completion. Recorder command
latency still applies. Existing cue sounds are reused before confirmed recording
and after confirmed pause.

Verified resume/pause requires an already active FocuSee recording session; it
does not create a new capture. Cloned takes use a separate fast state-confirmation
path: current recorder controls are freshly read, the shortcut is sent once only
from a confirmed opposite state, and confirmation polls until the target is
observed (up to two seconds), without the macOS path's fixed 500 ms sleep. Recorder
controls are cached by process/window identity, refreshed on each use, and
rediscovered when invalid. Unknown states never cause a blind toggle. Editor
playback controls are excluded. Existing macOS speech confirmation is unchanged.
Discovery includes app-level floating recorder children as well as AXWindows.
When fast discovery cannot recognize a state, a fresh read through the existing
detector preserves compatibility instead of guessing or sending a toggle.
Compatible discovery captures the exact AX attributes that supplied its state
evidence. Later samples reread those attributes instead of traversing the whole
interface, validating process identity, roles, visibility, live scopes, and the
ancestor/child topology first. Changed or invalid evidence forces rediscovery.
Both cached paths still classify fresh values and never toggle from a remembered
recording state.
A read-only startup warm-up primes controls and writes its observed state and PID
to `Runtime/cloned-focusee-state.json` beside the recording diagnostics.

Activity monitoring and WAV preparation happen before resuming capture. With zero
before-delay, playback uses the confirmation that just succeeded instead of
scanning FocuSee a second time. A nonzero before-delay still requires a fresh state
check afterward. The actual player's completion event starts
the finishing sequence. Transcription never controls duration. The panel shows
elapsed, remaining, and total audio time, preserving zero remaining while waiting
for screen actions to finish. Each take snapshots its settings and audio bytes.

**Stop Cloned Take** stops the WAV, cancels pending waits, and attempts a verified
pause when this take may have started or owned recording. Starting macOS speech
interrupts cloned playback and yields recording control to that original shortcut;
the cancelled cloned take does not send a late pause into the new workflow.
Generation/preview is blocked during a cloned take. Existing macOS speech settings
and bindings remain independent.

Live playback progress is also written atomically to
`~/Library/Application Support/local.clipboardreadermac/Runtime/approved-audio-recording.json`
with a session ID, audio version ID, stage, and actual player elapsed/remaining/
duration values. `timingEvents` records monotonic offsets for recorder checks,
commands, confirmations, playback request, first observed running playhead
(sampled every 100 ms), audio completion callback, and finishing actions. These
are software observations, not measurements of captured video frames or audible
speaker output. Critical start/stop transitions do not synchronously write the
feedback file; heartbeat/final publication carries the trace.
Lookup events include the path (`compatibleEvidenceCache`, scoped cache, or
discovery) and elapsed milliseconds. `audioOutputDiagnostics` records preparation
time, whether the output graph was warm, and the audio system's reported output/
device latency. Those latency values are diagnostics, not capture offsets used
to pause early; actual recorder/output behavior still needs a saved-footage test.
It contains no narration text. FocuSee command latency and enabled
finishing waits can still produce lead-in or tail footage; exact saved-footage
boundaries need a live recording test and are not guaranteed by these controls.

### Shortcuts and recording triggers

Under **Global shortcuts → Playback and scene shortcuts**, configure separate click, double-click, and hold actions for Back, Forward, and Middle. Defaults are Back click to replay the scene, Forward click to run the first current-input shortcut (including its recording actions), Middle click to read the on-screen instruction, and Middle hold to open the Scene Manager. Double-click actions default to None. Holds last at least 0.6 seconds; actions run on release. When a double-click is assigned, the single click waits 0.3 seconds for a possible second press. Set all three Forward or Middle actions to None to pass that button’s events through; plain Back remains reserved for shared routing. if Karabiner remaps a side button, the passed event remains F13 or F14. F13 and F14 also support the configured side-button actions. F15 supports the configured middle-button actions when Karabiner maps button3 to f15. These global mouse shortcuts require Accessibility permission. Control-modified side buttons are reserved for Neon Spotlight.

Choose **Toggle FocuSee Recording** to send the configured external Pause/Continue shortcut with a mouse gesture. This sends a toggle without checking the current recording state.

Fn + Back, Fn + Forward, and Fn + Middle can each be assigned separately. They default to None and run on button release; unassigned Fn combinations pass through. Fn availability on remapped side buttons depends on the mouse and Karabiner sending the Fn modifier with the F13/F14 event.

Narration Pilot provides two shortcuts for reading the current input and three shortcuts that always read the clipboard. Every read shortcut can use a different speed and choose an external action before and after speech: do nothing, toggle the configured shortcut, ensure FocuSee is recording, or ensure FocuSee is paused. Each action can use an independent 0–10 second delay so recording can settle before speech begins and continue briefly after speech ends. Existing trigger settings migrate to the original toggle behavior.

When **Ensure FocuSee is paused** is selected after reading, that shortcut can
optionally wait for Neon Spotlight. Narration Pilot checks Neon Spotlight's
local animation status after the normal post-speech delay and pauses FocuSee
only after every visible highlight and fade-out completes. The option defaults
off. If Neon Spotlight is closed, does not respond, quits, or remains busy for
more than 10 seconds, Narration Pilot safely continues with the verified pause.

Each shortcut can also optionally wait until mouse and keyboard activity has
stopped. The monitor starts only after speech, the configured delay, and any
Neon Spotlight wait. It observes mouse movement, clicks, scrolling, and key-down
activity without storing keys or text. Pointer movement below four points is
ignored to avoid sensor jitter. The quiet period defaults to one second and the
maximum wait defaults to 10 seconds; both are configurable in External Trigger
Shortcut settings and bounded to safe ranges.

The FocuSee actions inspect its macOS Accessibility controls before sending its existing Pause/Continue Recording shortcut. Separate global shortcuts can also be assigned for **Ensure FocuSee Recording** and **Ensure FocuSee Paused**. If FocuSee is closed, stopped, or its state cannot be determined safely, Narration Pilot does not send the toggle.

Optional recording cue sounds can play before FocuSee starts and after FocuSee is verified as paused. Start and stop cue timing is adjustable, and a separately selectable failure sound plays if a verified action fails. Narration is cancelled when FocuSee cannot be confirmed as recording.

The **Fix Latest FocuSee Zooms to 3 Seconds** project tool updates only generated zooms shorter than three seconds in the newest saved FocuSee project. Apply the default FocuSee preset and save the project first; Narration Pilot preserves the other project settings and creates a configuration backup before changing zoom tracks.

Sending external shortcuts requires macOS Accessibility permission. Narration Pilot requests that permission only when you ask it to.

## VS Code development

Open the repository and choose one of these tasks from **Terminal → Run Task**:

- **Dev Run Narration Pilot**
- **Dev Release Run Narration Pilot**

The Run and Debug panel also includes debug and release configurations for the `NarrationPilot` executable.

## Testing

```bash
swift build
swift build -c release
swift test
```

Some standalone Swift toolchains do not provide XCTest. In that environment the executable builds still work, but `swift test` reports `no such module 'XCTest'`.

## Privacy

Narration Pilot is local-first. Existing macOS speech passes text to macOS speech
services. Optional cloned clipboard generation sends the current narration to your
running Ultimate Video Editor instance and uses its configured TTS and MinIO
services; downloaded versions are retained locally. Narration Pilot contains no
analytics, accounts, or advertising.

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## License

Narration Pilot is open source under the [MIT License](LICENSE).

While FocuSee is recording, scene replay (including on-screen and code), scene navigation, script restart, and opening the Scene Manager are silently ignored. The same actions are blocked when FocuSee is open but its recording state cannot be determined. Pausing recording makes them available again.

Mouse action menus include Read Clipboard Always 1 and Read Clipboard Always 2, each using its existing speed and recording settings. Clipboard Always 1 is silently blocked during recording or an unknown FocuSee state, for both keyboard and mouse triggers. Clipboard Always 2 remains available.

Plain Back is shared with Neon Spotlight while both apps are running: during FocuSee recording it highlights in Neon Spotlight; while paused, stopped, or closed it uses the configured Narration Pilot Back gestures. Unknown recording state or a state check taking over 1.5 seconds silently blocks plain Back. Command + Back remains an explicit Neon Spotlight trigger. Ownership is retained until release. Forward, Middle, and Fn gestures keep their configured actions. Neon Spotlight must be enabled with its Back trigger enabled.

Shared Back uses a fresh recording-state check on press and checks again before dispatching a Narration Pilot action, including a delayed single click. Neon Spotlight derives hold duration from sender timestamps, receives held-state heartbeats, and releases a missing up event after 0.8 seconds without a heartbeat. Both apps must use the v2 routing protocol from the same update.

Neon Spotlight preview integration: Narration Pilot publishes speech/recording
activity locally once per second and when speech changes. FocuSee state checks
run on a utility queue, at most every two seconds, with a single request in flight;
slow checks fail closed. No narration or clipboard text is included. Neon uses
this to suspend hover previews and their tracking queries outside narration or
confirmed recording. Both apps must be updated for this integration.

Plain Middle Click / Karabiner F15 shares the existing fresh FocuSee-state router:
recording-owned gestures are relayed to Neon Spotlight's clipboard typing on
release. Paused/stopped gestures retain configured click/double/hold actions and
are rechecked before dispatch. Unknown state is ignored. Fn gestures remain on
their existing path. Both updated apps must be running for the shared route.


## Reliable installation and startup

Build the complete bundle with `scripts/build-app.sh release`, then install it
with `bash scripts/install-app.sh release`. The installer validates signatures
and bundle identity, stages the complete app, stops existing processes, replaces
the canonical `/Applications` app, verifies the executable, and retains a rollback
bundle outside Launch Services' normal `.app` naming. A failed replacement restores
the previous installed bundle. Finder's bundle modification date is refreshed.
`BuildRevision` and `BuildDateUTC` in Info.plist identify the build precisely.

New build-folder app copies redirect to the installed app before initializing
shortcuts. A per-user kernel lock prevents simultaneous new instances, and releases
automatically on exit/crash. Historical binaries predating this guard should not
be launched; the normal debug bundle is refreshed by the release installer.

Input health is checked every two seconds, with retries after permission becomes
available. Wake/session activation resets interrupted input and requests recovery.
Narration Pilot also re-registers its saved keyboard shortcuts after wake.

Quiet diagnostics (no clipboard/narration text) are stored at:

`~/Library/Application Support/local.clipboardreadermac/Runtime/status.json`

The file contains running path, PID, version/build revision/date, Accessibility
trust and actual event-tap health. Permission reports/tap creation do not prove
physical shortcut behavior. Login, wake, recording and mouse behavior require a
physical test.

Set `APP_SIGNING_IDENTITY` to a valid installed signing identity when building.
The fallback remains ad-hoc signing and does **not** guarantee preserved macOS
permissions across changed builds. No custom weaker designated requirement or
TCC reset is used. A valid consistent certificate must be available to investigate
permission preservation further; no certificate is created automatically.
