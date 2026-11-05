---
name: guided-scene-recording
description: Run Sahand’s hands-free Narration Pilot workflow using spoken wording review, approved cloned audio, voiced practice, and A/G approval to record. Use for the new guided scene-by-scene workflow and its persistent runner; keep the earlier macOS-speech/loaded-script recording skill separate.
---

# Guided scene recording

Use a prepared scene and one persistent runner to minimize delay between Sahand’s A/G decisions. Keep Codex minimized during practice/recording. This is a new workflow: **do not modify `record-narration-pilot-tutorial` or its resources**. Do not substitute that older skill’s silent rehearsal or Command–2/3 speech shortcuts for this workflow.

## The user’s controls

Narration Pilot announces the active stage. Read actual saved bindings; Sahand currently uses Command–Shift–A and Command–Shift–G.

- Wording: A approves exact narration; G requests improvement from the active agent.
- Audio: wording approval automatically prepares/plays cloned audio; A approves the exact candidate; G regenerates the same wording/voice.
- Practice: play the approved WAV while the runner performs planned screen actions with FocuSee paused. G repeats practice with the same audio. A approves the practiced plan and requests recording after restoration.
- Recording: restore the original starting screen/cursor, verify it, then record the same plan and WAV. Let Narration Pilot handle resume/pause and its configured idle wait. Never synthesize A/G or treat a timeout as approval.

Do not ask for a typed duplicate of an approval already saved by the app. Use spoken app prompts and stage events. Talk in chat only for a decision not expressible with those controls, a meaningful blocker, or a compact result.

## Prepare before the user waits

Read [references/runner.md](references/runner.md) for the scene format, commands, and evidence bridge. The app repository is `/Users/sahand/Desktop/projects-test/narration-pilot`; the skill’s `scripts/session.py` wraps its runner helper. An explicit `NARRATION_PILOT_REPO` can override that path.

1. Confirm the installed app’s live feedback is fresh, existing narration idle, and FocuSee observed paused. Sahand prepares/restarts FocuSee and handles protected permission prompts. Ordinary recording does not authorize rebuilding apps, changing settings, or installing dependencies.
2. Identify the intended visible actions from the actual screen and proposed narration. Use the existing AgentCursor SDK for all mouse actions; CUA is for read-only evidence and supported native keyboard input. Chrome is the tutorial browser. Keep other user work intact.
3. Author the reusable action/restore recipe **before** starting spoken review where possible. Bind visible stable targets early; mark targets that appear only after transitions as deferred. Native AgentCursor modules and targets warm during preparation. The runner stays alive across scenes and resets its movement seed per attempt.
4. For an initial scene, establish its starting checkpoint while paused. For an appended scene, use the previous take’s actual ending checkpoint; never replace it with rehearsal results. Supply `baselinePath` when inheriting one. Window geometry, selected tabs, visible state, focus/selections, and actual cursor must match. All demonstrated app/tab/page transitions happen during practice and recording, not only setup.
5. Start the runner once and prepare the scene. When it reports prepared, submit the exact narration to the existing guided-review helper using the same session ID. For a familiar surface, preparation can overlap wording/audio review while capture is paused. Do not announce practice ready before the actions and checkpoint are prepared.

## Run the prepared flow

- The persistent process consumes app practice/record requests, resolves the approved word timings to the authored cues, restores the checkpoint, verifies fresh evidence, plays the WAV, executes real cursor actions, and reports action results. Use the WAV player clock for synchronization; transcription guides actions and never determines the hard stop.
- Follow `session.py wait --after-sequence ...` while the process handles A/G without additional model/tool orchestration. It stays responsive to changed run IDs and aborts stale work. Do not start another worker for each take or rebuild per-scene scripts after audio approval.
- A `narrationImprovementRequested` event needs the agent. Acknowledge the matching wording event, improve the narration, and submit revision +1 through `guided-narration-review.py`. The worker detects the revision and resumes. Update action cues before practice if the wording/action plan changed.
- A missing word cue or meaningful screen mismatch stops for agent help. Correct the specific issue while paused. `update` changes actions only before a new practice; `resume` retries a repaired continuity gate. Never alter a practiced plan after its recording approval or ignore a changed tab/window merely to make checks pass.
- Perform visible typing character by character and trackpad scrolling through AgentCursor. Aim to finish meaningful actions before audio ends; existing recording idle waiting can extend capture for late actions. A missed action or premature pause requires a corrected practice/retake, not a patched recording.
- Only reusable, reversible, practice-safe actions belong in the automatic runner. Do not rehearse Send, destructive actions, purchases, or irreversible operations. Split such steps for separately authorized agent handling; do not label them practice-safe to bypass this boundary.

## Fresh visual evidence and completion

The runner automatically checks stable AX state, geometry, cursor and window images. Only explicitly documented cosmetic regions may be masked; never mask selected tabs, narration-relevant content, focus, or meaningful controls.

If native screenshot access is unavailable, use the documented CUA image request. Supply fresh screenshots for the exact request, then let the worker compare them. **Do not bypass permissions, reuse old images as current evidence, or replace visual checks with AX-only assertions.** This fallback requires the active agent but no additional user approval.

The worker saves an operational ending checkpoint after recording and observed pause, before further UI actions. Its `footageNeedsReview` flag is intentional: playback/AX logs do not prove saved-footage quality. At a test/chapter boundary, request normal footage review; do not stop/export/edit the capture unless asked. An uncertain ending state must be resolved before the next scene.

Keep one process for the session. End the completed guided review before preparing the next scene, then reuse the saved ending checkpoint and runner. Stop the runner when the recording session ends; an active capture is aborted through the app’s verified pause cleanup. New narration and repairs need an active agent: the worker does not wake an ended chat or autonomously invent scenes.
