# Prepared session runner

Use the repo’s `scripts/guided-session.py` (or the skill wrapper). Runtime files are private under `~/Library/Application Support/local.clipboardreadermac/GuidedSessionRunner/`. No new server or external model API is used. The existing app must support guided practice.

## Start and prepare

```sh
python3 /Users/sahand/.codex/skills/guided-scene-recording/scripts/session.py start
python3 /Users/sahand/.codex/skills/guided-scene-recording/scripts/session.py prepare --scene-file /absolute/work/scene.json
python3 /Users/sahand/.codex/skills/guided-scene-recording/scripts/session.py wait --timeout 55 --after-sequence -1
```

Choose a fresh session UUID and author the scene file from the live UI. A minimal Calculator-style example (labels must be verified on the current Mac):

```json
{
  "sessionID": "YOUR-SESSION-UUID",
  "sceneID": "calculator-test",
  "startingApp": "Calculator",
  "observeApps": ["Google Chrome", "Calculator"],
  "seed": 4103,
  "pacing": {"reaction": 0.15, "speed": 2, "dwell": 0.6},
  "actions": [
    {"id":"one","description":"Click 1","verb":"click","target":{"name":"1","role":"button"},"cue":{"words":["twelve","12"],"leadSeconds":0.6},"practiceSafe":true},
    {"id":"two","description":"Click 2","verb":"click","target":{"name":"2","role":"button"},"cue":{"words":["twelve","12"],"leadSeconds":0.2},"practiceSafe":true},
    {"id":"plus","description":"Click Add","verb":"click","target":{"name":"Add","role":"button"},"cue":{"word":"and","leadSeconds":0.2},"practiceSafe":true},
    {"id":"eight","description":"Click 8","verb":"click","target":{"name":"8","role":"button"},"cue":{"words":["eight","8"],"leadSeconds":0.2},"practiceSafe":true},
    {"id":"equals","description":"Click Equals","verb":"click","target":{"name":"Equals","role":"button"},"cue":{"word":"equals","leadSeconds":0.5},"practiceSafe":true}
  ],
  "restoreActions": [
    {"id":"clear","verb":"click","target":{"name":"All Clear","role":"button"},"practiceSafe":true}
  ]
}
```

`cue.words` are alternative spellings of one spoken token; matching ignores case/punctuation. `occurrence` is one-based (default 1); `leadSeconds` begins an action before the word so cursor travel can finish near it. Alternatively use `atSeconds`. Timing resolves only after the exact audio/word timings are approved. Pacing is optional; tune it through practice, not an unapproved recording change.

Supported verbs: click, move, type, key, scroll, activate, hold. Stable named targets are cached from early observation; `deferred:true` resolves a target freshly after a visible transition. Coordinate targets require current visual grounding. Type uses `text` and never submits; keys use `key`; scroll uses AgentCursor `scroll` options and trackpad style. Every automatic action must be practice-safe. Keep `restoreActions` explicit and reversible. Initial setup is separate from actions that viewers must see.

A restore action may include `whenWindowTitleExcludes`: it runs only when a fresh AgentCursor window title lacks that text. Use this for idempotent restoration, so the first practice does not navigate away from an already correct start. This does not relax the subsequent continuity gate.

The first baseline is immutable. An inherited `baselinePath` points to the prior ending-checkpoint JSON; the current screen must match it. Use `cosmeticMasks` only for observed transient non-content differences: per-app arrays of `{"rect":[x,y,width,height],"reason":"specific cosmetic difference"}` in normalized image coordinates. Default is strict comparison. Each region is limited to 8% of the image; that bound does not make a semantically important mask acceptable.

Once prepared, submit narration:

```sh
python3 /Users/sahand/Desktop/projects-test/narration-pilot/scripts/guided-narration-review.py submit --session-id YOUR-SESSION-UUID --scene-id calculator-test --text "Let's add twelve and eight in Calculator. Click equals. The answer is twenty."
```

The same worker then handles practice, G redo, and A-to-record. It never sends those approval shortcuts. Physical keys are handled by Narration Pilot.

## AgentCursor screenshots only

Use AgentCursor for all GUI inspection and actions. Before the initial baseline, run a real SDK screenshot and verify it succeeds, with transient overlays removed and editable fields defocused when no typing is intended. Inspect the returned local image as needed. Computer Use/CUA is not used in this workflow.

If native capture fails, report the concrete permission state and let Sahand handle the macOS permission UI. The runner still has a legacy supplied-image mechanism for isolated checks; `needsEvidence` is not permission to switch to Computer Use. Do not supply stale images or assert visual matching from AX alone.

Browser rehearsal can change incidental history, tracking parameters, visited-link styling, or hover status text. Avoid repeated blind attempts to reverse those changes. If strict comparison stops, use fresh AgentCursor screenshots and live controls to inspect and restore the meaningful starting page, query, visible target/layout, focus and cursor. An agent-authored gate must preserve the practiced checkpoint ID and save the actual images, observations, and explicitly reviewed incidental differences. Do not accept a different page, query, missing target, changed layout, or a hidden recording overlay as cosmetic.

## Events, repairs, and shutdown

`wait` is bounded to 60 seconds and wakes for prepared, needsEvidence, needsAgent or sceneComplete. Carry forward `sequence` with `--after-sequence` to suppress old events. Waiting is not approval.

A `narrationImprovementRequested` event includes the app’s exact decision. Acknowledge and submit revision +1 using `guided-narration-review.py`; the runner detects the revision. If action cues changed, `update --scene-file ...` is allowed only before a new practice. It preserves the baseline and cannot replace an accepted recording plan. After repairing a stopped continuity gate, `resume` retries it; no approval is invented.

`sceneComplete` points to `endingCheckpoint`. It includes actual ending state and `footageNeedsReview:true`; retain that limit in reports. End the completed app review through `guided-narration-review.py end --session-id ...` before preparing the next scene. Keep the worker process alive and reuse the ending checkpoint for continuity. Prefetch the next existing Baserow row and chapter-end status during current audio generation/review. Once recording finishes and FocuSee is observed paused, immediately submit that stored narration for spoken review; finish action preparation during the new wording/audio review. Do not write fresh next-scene narration or wait for a routine chat/footage-review approval. At the verified end of the chapter, promptly announce “Recording completed for this chapter” using the existing macOS speech announcement path, leave FocuSee paused, and end the guided review. Do not infer completion from a failed fetch or a blank expected narration row.

```sh
python3 /Users/sahand/.codex/skills/guided-scene-recording/scripts/session.py status
python3 /Users/sahand/.codex/skills/guided-scene-recording/scripts/session.py stop
```

No batch of unseen scenes, automatic app rebuild, or footage deletion is authorized by this skill.
