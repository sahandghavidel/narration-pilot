---
name: youtube-narration-script-builder
description: Create a complete video outline and all narration scenes for a requested chapter in Narration Pilot Baserow before recording. Keep On Screen empty so the agent improvises screen actions, then record scene by scene from the saved narration with A/G approvals. Use the original youtube-tutorial-script-builder for fully authored visual scripts instead.
---

# YouTube Narration Script Builder

This is a separate narration-only adaptation of `youtube-tutorial-script-builder`. Preserve that original skill, `record-narration-pilot-tutorial`, and the separate `guided-scene-recording` skill unchanged when maintaining this skill.

The workflow has two phases: **create the complete requested chapter’s narration first, then record its saved scenes**. Do not create only one scene and treat it as a complete chapter. Screen-action writing remains omitted.

Read [references/project-workflow.md](references/project-workflow.md) for chapter preparation and progression, and [references/narration-pilot-baserow.md](references/narration-pilot-baserow.md) before Baserow reads or writes. Use `$write-like-sahand` for narration and `$guided-scene-recording` for A/G review, audio, practice, timing, continuity, and actual recording.

## Phase 1 — Create the complete chapter

1. Use Baserow as the permanent source of truth: one video in `Narration Pilot Scripts` (740), with ordered scenes linked to it in `Narration Pilot Scenes All Scripts` (739). Find the matching script before creating one. Maintain a concise complete video outline.
2. For a new video, draft **every narration scene needed to complete Chapter 1**. For a continuation, draft every scene of the requested chapter. Do not draft future chapters unless requested, and do not stop after the opening scene. A request to create an outline and start a chapter means prepare that complete chapter’s narration; it does not automatically start screen recording.
3. Inspect existing linked scenes and user edits first. Preserve approved/recorded scenes and other chapters. If the requested chapter is partial, reconcile its existing content with the outline and complete the missing narration without duplicating or silently rewriting preserved scenes.
4. Keep each narration concise and focused on a goal, explanation, action, or result. Cover the chapter’s full stated goal and final useful outcome without padding. Separate meaningful actions and their results; verify facts and feasibility against the actual software/site. Leave **On Screen empty** for new rows. Do not write click directions, action plans, checkpoints, timing logs, or recording status into On Screen or Annotation.
5. Validate the **whole proposed chapter** before the first scene write: coverage, sequence, links, continuous Scene Number across the complete script, correct Part, nonblank narration, and no unintended edits. Save all its narration rows in Baserow, not just its first scene. Draft text may be saved before A approval; saving does not imply wording, audio, practice, or recording approval.
6. Re-fetch and verify the complete saved chapter against the validated scene list. Retain its expected row IDs/count and final scene ID in private recording runtime metadata, preserving existing take metadata. Announce chapter preparation complete only after every planned row is verified. Partial writes or missing rows mean preparation is unfinished; reconcile them before starting recording.

Do not create local script drafts, chapter folders, or duplicate script exports unless Sahand requests an export. Private recording recipes, checkpoints, and chapter/row mappings are runtime metadata, not a second permanent script.

## Phase 2 — Record from the saved chapter

1. When recording is requested, confirm the complete chapter is prepared and read its existing rows in Scene Number order. Start guided wording review with the exact saved narration. Do not invent another scene just because a take finished.
2. G requests an improved version of the current row. A approves exact wording and triggers cloned audio through the existing app. While audio generates, save any approved narration revision back to the same Baserow row. Unchanged wording needs verification, not a redundant write. Audio regeneration creates no script rows and changes no approved wording.
3. During current audio preparation/review, prefetch the next existing narration and chapter-end status, retaining row ID and Last Edited. This is reading ahead, not writing new narration or generating unapproved cloned audio. Prepare live screen actions during this same waiting time.
4. After actual recording completion and confirmed FocuSee pause, retain the row and actual ending checkpoint, then immediately announce the prefetched next narration through guided review. Do not wait for a chat reply, routine footage review, full action-plan preparation, or nonessential bookkeeping. Practice still requires prepared actions and a verified starting state.
5. After the prepared chapter’s verified final scene and earlier scenes are recorded, promptly announce “Recording completed for this chapter.” Leave FocuSee paused. Do not infer the chapter is finished merely because the currently saved rows end; compare against the prepared chapter’s expected row set. A blank expected row, incomplete preparation, or failed read is a data problem, not completion. Do not silently enter the next chapter or treat recorded completion as editorial approval.

Re-fetch the live schemas, selected script, and all linked scenes immediately before each database mutation; verify each saved result. Preserve a stable scene-to-row mapping so retries and revisions cannot create duplicates. Save failures must be tracked and resolved while paused without delaying ordinary audio playback; report an unresolved save before continuing.

## Improvise screen actions, preserve recording accuracy

No advance On Screen writing is required. Determine actions from the saved narration and current UI. Prepare the minimal executable recipe required by the guided runner, practice it with the actual approved WAV, and freeze it after practice approval. Improvisation does not authorize a different unpracticed plan during recording.

A scripted result is planned narration, not evidence that a new operation succeeded. Before speaking or recording it, verify the actual screen supports it. Resolve unexpected state or follow an explicit revision request; never invent a successful download or installation.

## Resume and report

A new chat reads the selected script, outline, complete linked chapter, and preparation/take metadata, then checks actual app evidence to establish the next unfinished scene. Saved draft narration is not proof of approval or recording. If completeness metadata is missing, reconcile the chapter against its outline before claiming it is ready or finished.

Store take references only in genuine purpose-specific schema fields or private guided runtime, never in Annotation or invented fields. This skill coordinates saves while an agent is active; it does not add an app-wide background Baserow writer.

At a checkpoint, return `http://localhost:9540/narration-scripts?script=SCRIPT_ID` (and `&scene=SCENE_ID` when useful). Distinguish a prepared chapter from a recorded chapter. Do not paste the whole script unless asked.
