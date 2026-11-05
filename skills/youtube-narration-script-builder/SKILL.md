---
name: youtube-narration-script-builder
description: Keep a YouTube tutorial outline and a running record of approved narration in Narration Pilot Baserow while Sahand records scene by scene. Use when the agent improvises screen actions and the user wants minimal advance writing with no On Screen instructions. Use the original youtube-tutorial-script-builder for fully authored visual scripts instead.
---

# YouTube Narration Script Builder

This is a separate narration-only adaptation of `youtube-tutorial-script-builder`. Preserve that original skill and `record-narration-pilot-tutorial` unchanged. The purpose is **recordkeeping during recording**, not preparing a full script before recording.

## Prepare only what is needed

Read [references/project-workflow.md](references/project-workflow.md) for the chapter loop and [references/narration-pilot-baserow.md](references/narration-pilot-baserow.md) before Baserow reads or writes.

Use Baserow as the permanent source of truth: one video in `Narration Pilot Scripts` (740), and ordered narration rows linked to it in `Narration Pilot Scenes All Scripts` (739). Find the matching script before creating one. Maintain a concise complete outline; start Chapter 1 with its first narration, not a prewritten chapter of detailed scenes. For recording, read the existing linked scene narration from Baserow in Scene Number order. Do not invent or draft a next scene because recording finished. Author new narration only when Sahand explicitly requests script creation; revise existing wording only for a G improvement request or another explicit revision request.

Use `$write-like-sahand` for narration and `$guided-scene-recording` for live A/G review, audio, practice, timing, continuity, and actual recording. The narration skill does not replace that recording mechanism or its approval gates.

## Save while audio prepares

1. Fetch the selected script’s existing ordered narration and start guided review with the exact current row text. G requests a better version of that row. During audio generation/review, prefetch the next existing row in the same chapter and its chapter-end status, retaining row ID and Last Edited. This is reading ahead, not writing new narration or pre-generating unapproved cloned audio. Do not save rejected wording as the approved script.
2. When the app saves the real user's **wording approval**, use that exact event's narration, revision, and scene identity. Audio generation starts through the existing app; concurrently save the approved narration and chapter/scene relationship through direct Baserow REST calls. Do not wait for audio approval to preserve approved wording.
3. Reuse the existing scene row. Verify unchanged approved wording without a redundant write; patch only Narration when an approved revision changes it. Create a new linked row only when script creation was explicitly requested. Re-fetch the live schema, selected script, and all its linked scenes immediately before each write. Verify the saved result. Keep a stable guided-session/scene-to-row mapping in the private recording runtime so audio retries cannot create duplicate scenes.
4. Leave **On Screen empty** for newly created rows. Do not write click-by-click directions, action plans, checkpoints, timing data, or recording logs into On Screen or Annotation. Preserve existing nonempty fields unless Sahand explicitly authorizes changing them. No Code or code metadata is needed for ordinary click tutorials; add only what is explicitly requested.
5. Continue audio review, voiced practice, and recording through the guided workflow. Audio regeneration changes no approved narration row. Use the generation wait to inspect the live interface and prepare only the reversible actions needed for the current scene. Do not delay playback for recordkeeping; track a failed save and retry with a fresh read while capture is paused, reporting any unresolved unsaved scene before continuing.
6. After actual recording completion and confirmed FocuSee pause, retain the same row and ending checkpoint, then immediately announce the prefetched next existing narration through guided review. Do not wait for a chat reply, routine footage review, full action-plan preparation, or nonessential bookkeeping. Prepare the screen actions during wording/audio review and validate them before practice. If the completed row is the last existing scene in the chapter and earlier chapter scenes are recorded, promptly announce “Recording completed for this chapter.” Keep FocuSee paused; do not invent another narration, silently enter the next chapter, or treat completion as editorial approval. A blank expected row or failed Baserow read is a missing-narration/data problem, not proof of chapter completion.

## Improvise screen actions, preserve recording accuracy

No advance On Screen writing is required. Determine the screen actions from the approved narration and current UI. Prepare the minimal executable recipe required by the guided runner, practice it with the actual approved WAV, and freeze it after practice approval. This private runtime recipe is allowed and is not a second permanent script. Improvisation does not authorize a different unpracticed plan during the approved take.

Keep one meaningful focus per narration: goal, explanation, action, or result. Chapter openings may use a short goal and a useful foundation explanation. Do not pad a short demonstration with extra scenes. Show meaningful action and result separately when narrating them. Check factual claims and actual visible controls; never invent a successful download or installation.

## Resume and report

A new chat reads the selected script, outline, and complete linked narration sequence, then checks actual app/runtime recording evidence to establish the next unfinished scene. A saved narration alone proves wording was saved, not that audio or recording was approved. Store approval/take metadata only in schema fields that genuinely exist or in the private guided runtime, never in invented fields or Annotation. Do not claim this skill adds an app-wide background Baserow writer: it performs the saves while an active agent is working.

At a checkpoint, return `http://localhost:9540/narration-scripts?script=SCRIPT_ID` (and `&scene=SCENE_ID` when useful). Do not paste the whole script unless asked. State any unresolved Baserow save separately from recording success.
