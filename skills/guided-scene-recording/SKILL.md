---
name: guided-scene-recording
description: Run Sahand’s hands-free Narration Pilot workflow using spoken wording review, approved cloned audio, voiced practice, and A/G approval to record. Use for the new guided scene-by-scene workflow and its persistent runner; keep the earlier macOS-speech/loaded-script recording skill separate.
---

# Guided scene recording

Use a prepared scene and one persistent runner to minimize delay between Sahand’s A/G decisions. Keep Codex minimized during practice/recording. This is a new workflow: **do not modify `record-narration-pilot-tutorial` or its resources**. Do not substitute that older skill’s silent rehearsal or Command–2/3 speech shortcuts for this workflow.

Minimize Codex once before the first checkpoint and keep it minimized for the entire session, including A/G review, redo, recording, and scene transitions. Do not activate or restore it for screenshots, status checks, or routine restoration. The persistent runner remembers the initial minimization; later gates minimize again only when fresh app state shows Codex has become the foreground app. If it was deliberately reopened for a repair, minimize it again while capture is paused before resuming. Continue evidence collection and tool work in the background.

## The user’s controls

Narration Pilot announces the active stage. Read actual saved bindings; Sahand currently uses Command–Shift–A and Command–Shift–G.

- Wording: A approves exact narration; G requests improvement from the active agent.
- Audio: wording approval automatically prepares/plays cloned audio; A approves the exact candidate; G regenerates the same wording/voice.
- Practice: play the approved WAV while the runner performs planned screen actions with FocuSee paused. G requests improved screen actions with the same approved audio. Review the previous attempt and any feedback, change what viewers see or its timing, restore the same starting checkpoint, and practice the revision before A can record it. A approves the practiced plan and requests recording after restoration.
- Recording: restore the original starting screen/cursor, verify it, then record the same plan and WAV. Let Narration Pilot handle resume/pause and its configured idle wait. Never synthesize A/G or treat a timeout as approval.

Do not ask for a typed duplicate of an approval already saved by the app. Use spoken app prompts and stage events. Talk in chat only for a decision not expressible with those controls, a meaningful blocker, or a compact result.

## Chapters started in the app

When guided status includes `remainingChapterScenes` (including an empty array), the app owns scene selection. Use the active draft and session ID. Do not submit a new first draft, end the review between scenes, or announce chapter completion yourself. The app loads the selected Baserow rows independently of the macOS reader. G during wording review still requires the matching agent revision.

When recording together, start an interruptible `session.py listen` and keep the chat turn active. It waits across manual takes, next-scene reads, silence and chapter completion. On a practice request, use the returned current draft and run ID, start/reuse the runner, prepare and perform that scene's practice, and follow its A/G decisions. On a revision request, answer its exact event. After servicing either request, resume listening. Answer side questions and keep waiting. Only finish the chat when Sahand ends the session or his explicit endpoint is reached. A detached listener alone cannot keep a finished agent turn alive.

At the cloned-voice preview, M (Command–Shift–M or Control–Shift–M) approves the voice for a manual take. Leave the screen and cursor to Sahand. The app records and advances after confirmed pause. Wait for A to request guided practice before preparing a desktop plan or touching the screen in this mode. Use the last guided ending checkpoint if it immediately preceded this scene. After a manual take, establish the new checkpoint from the actual screen left by Sahand. After a guided take the app starts the next spoken review, or announces final chapter completion, as soon as the approved audio and actions finish and pause is verified. The runner saves the ending checkpoint in parallel and releases the next screen action. If ending capture fails, repair it while paused and resume the runner to save the ending without recording again. With no active agent, manual chapter recording still runs; wording revisions and guided practice wait for assistance.

## Prepare before the user waits

Read [references/runner.md](references/runner.md) for the scene format, commands, and evidence bridge. The app repository is `/Users/sahand/Desktop/projects-test/narration-pilot`; the skill’s `scripts/session.py` wraps its runner helper. An explicit `NARRATION_PILOT_REPO` can override that path.

1. Confirm the installed app’s live feedback is fresh, existing narration idle, and FocuSee observed paused. Sahand prepares/restarts FocuSee and handles protected permission prompts. Ordinary recording does not authorize rebuilding apps, changing settings, or installing dependencies.
2. Identify the intended visible actions from the actual screen and proposed narration. Use the existing AgentCursor SDK for all GUI actions, native keyboard input, screen inspection, and screenshots. Do not use Computer Use/CUA as a fallback. Viewing an image already captured by AgentCursor is allowed. Chrome is the tutorial browser. Keep other user work intact.
3. Prepare the reusable action/restore recipe during existing audio/review waiting time where possible. Prefetch the next existing Baserow narration and chapter-end status during that same idle time; do not author a replacement next narration. Bind visible stable targets early; mark targets that appear only after transitions as deferred. Native AgentCursor modules and targets warm during preparation. The runner stays alive across scenes and resets its movement seed per attempt.
4. For an initial scene, establish its starting checkpoint while paused. For an appended scene, use the previous take’s actual ending checkpoint; never replace it with rehearsal results. Supply `baselinePath` when inheriting one. Window geometry, selected tabs, visible state, focus/selections, and actual cursor must match. All demonstrated app/tab/page transitions happen during practice and recording, not only setup.
5. Keep one runner for the session. Use the exact existing Baserow narration with the correct guided session/scene identity. After the preceding take completes and pause is confirmed, begin spoken review promptly from the prefetched row; finish action/restore preparation during wording/audio review. Do not delay this handoff for full plan preparation or routine reporting. Practice still requires a prepared plan and verified starting checkpoint.

## Startup and retry discipline

Before saving the first checkpoint, initialize the visual-evidence tool and settle the intended foreground app. Verify an actual AgentCursor screenshot before saving the baseline. If native capture is unavailable, report its permission failure and let Sahand handle the macOS prompt; do not switch to Computer Use/CUA. Complete initial permission/capture preflight before the first scene. For later scenes, spoken wording review may start as soon as the preceding recording has completed and FocuSee is confirmed paused; practice waits for the runner to be prepared.

Use a fresh session UUID and revision 1 for every new review, including a review restarted after `end`. Revisions within an active review follow the matching improvement event. A new review may reuse cached approved audio, but it must receive its own real user approvals.

A previous take’s idle timing file can be old. The runner must wait for new playback progress before acting; do not treat the old file as failed playback or add a fixed recording delay. Keep current-run and approved-audio identity checks, actual player timing, and fresh capture feedback. Run `scripts/checks/GuidedSessionRunnerCheck.py` after changing this startup logic; it covers an old timing file before a new take.

For a foreground/checkpoint failure, keep capture paused, inspect the actual difference, and allow one diagnosed retry. If it repeats, stop and report the specific failure rather than repeatedly restarting workers. An initial checkpoint may be established again before any review/practice; an inherited or already practiced checkpoint must be restored, never rebased to hide a mismatch. After an aborted take, verify pause and return to real-user-approved practice; do not reuse the prior A decision to silently record again.

## Run the prepared flow

- The persistent process consumes app practice/record requests, resolves the approved word timings to the authored cues, restores the checkpoint, verifies fresh evidence, plays the WAV, executes real cursor actions, and reports action results. Use the WAV player clock for synchronization; transcription guides actions and never determines the hard stop.
- Follow `session.py wait --after-sequence ...` while the process handles A/G without additional model/tool orchestration. It stays responsive to changed run IDs and aborts stale work. Do not start another worker for each take or rebuild per-scene scripts after audio approval.
- A `narrationImprovementRequested` event needs the agent. Acknowledge the matching wording event, improve the narration, and submit revision +1 through `guided-narration-review.py`. The worker detects the revision and resumes. Update action cues before practice if the wording/action plan changed.
- For a `practiceImprovementRequested` event, submit the revised scene with `session.py update --scene-file PATH --run-id RUN_ID`. Keep listening while Sahand decides.
- A missing word cue or meaningful screen mismatch stops for agent help. Correct the specific issue while paused. `update` changes actions only before a new practice; `resume` retries a repaired continuity gate. Never alter a practiced plan after its recording approval or ignore a changed tab/window merely to make checks pass.
- For demonstrated search or text entry, move the real pointer to the visible field and click it before typing. Prefer clicking an already visible matching suggestion when that demonstrates the requested search. Reserve focus shortcuts for scenes that teach them. Perform visible typing character by character and trackpad scrolling through AgentCursor. Aim to finish meaningful actions before audio ends; existing recording idle waiting can extend capture for late actions. A missed action or premature pause requires a corrected practice/retake, not a patched recording.
- Only reusable, reversible, practice-safe actions belong in the automatic runner. Do not rehearse Send, destructive actions, purchases, or irreversible operations. Split such steps for separately authorized agent handling; do not label them practice-safe to bypass this boundary.

## Fresh visual evidence and completion

The runner automatically checks stable AX state, geometry, cursor and window images. Only explicitly documented cosmetic regions may be masked; never mask selected tabs, narration-relevant content, focus, or meaningful controls.

If AgentCursor screenshot access is unavailable, stop screen actions and report the actual permission failure. A legacy `needsEvidence` request is not authorization to use Computer Use/CUA. Never bypass permissions, reuse an old image as current proof, or replace visual checks with AX-only assertions.

The worker saves an operational ending checkpoint after recording and observed pause, before further UI actions. Its `footageNeedsReview` flag is intentional: playback/AX logs do not prove saved-footage quality. The `footageNeedsReview` flag alone does not block continuation or require a chat question. After actual recording completion and observed pause, retain the ending checkpoint and immediately speak the prefetched next existing Baserow row within the current chapter; A/G remain the normal approvals. Read ahead while the current audio generates/reviews rather than drafting new wording after every take. If the successfully recorded row is the chapter’s verified final scene, promptly announce “Recording completed for this chapter” through the existing macOS speech announcement path and leave capture paused. Do not create a fake scene or cloned audio for this status message. Missing/blank expected narration or a failed data read must be reported as a blocker, not announced as completion. Do not stop/export/edit the capture or add a separate footage-review approval unless Sahand asks. Resolve a genuine wrong screen, missing action, or uncertain ending state through current AgentCursor evidence before continuing, and report an unresolved failure clearly.

Keep one process for the session. End the completed guided review before preparing the next scene, then reuse the saved ending checkpoint and runner. Stop the runner when the recording session ends; an active capture is aborted through the app’s verified pause cleanup. Existing-row handoff, requested wording improvements, and repairs need an active agent: the worker does not wake an ended chat or autonomously invent scenes.
