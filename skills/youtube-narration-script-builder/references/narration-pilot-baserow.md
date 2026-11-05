# Baserow narration record

## Existing tables and access

- Narration Pilot Scripts — 740: Script Title, Outline, Status, Date, Last Edited, reciprocal scenes.
- Narration Pilot Scenes All Scripts — 739: Scene Number, Script, Part, Narration, On Screen, Annotation, Code and metadata, Last Edited.
- Review link: http://localhost:9540/narration-scripts?script=SCRIPT_ID

Retrieve and mutate data with direct authenticated Baserow REST requests using existing local configuration. Do not use the browser Narration Scripts page to inspect or edit database records. Never print credentials. The editor's configured BASEROW_API_URL may include `/api`; normalize paths without adding it twice. Preserve the configured hostname/Host route: this local server can return an HTML “Site not found” page when `localhost` replaces `host.docker.internal`.

## Reads and writes

Read live schemas with GET /api/database/fields/table/740/ and /739/. Use `user_field_names=true` for row operations. Fetch all pages of script rows and find the matching title; do not assume an existing related tutorial is this new video's script. Immediately before every write, re-fetch the live schemas, selected script (when created), and every page of linked scene data. Select scenes only where Script contains the intended script ID.

POST /api/database/rows/table/{table}/ creates a row. PATCH /api/database/rows/table/{table}/{row}/ updates identified fields. After writing, re-fetch and verify exact values, links, Part and unique continuous Scene Number. Never reuse, move, overwrite, renumber, clear, or delete another script's rows.

During recording, reuse the existing linked row; an unchanged wording approval needs verification, not another row. New scenes require an explicit script-creation request. A new scene payload contains its continuous Scene Number, Script:[scriptID], Part, approved Narration, and empty On Screen/Annotation/code fields where present and writable. Use only actual schema fields. Save each row once per logical scene. Preserve its row ID in private runtime metadata mapped to guided session and scene; revisions patch the same row and audio regeneration does not write a new row. On an uncertain POST result, re-read linked rows and reconcile the exact chapter, number and narration before retrying; do not issue a blind second POST.

## Approval and validation

Validate the current proposed narration and its link/number before creating the row; there is no full-chapter On Screen validation. Confirm the wording came from the current approval event, uses one meaningful focus, and does not assert an unobserved result. Leave On Screen empty; action selection is handled live by the recording agent. Annotation is reserved for actual user annotations, not internal status or records. Preserve existing annotations and other fields during narration-only PATCHes.

When revising already saved narration, honor user edits fetched immediately before the write. If the live text differs from the expected original, reconcile rather than overwrite it. Audio and take references may be written only to genuine purpose-specific live fields. If unavailable, retain them in guided runtime evidence; do not claim the narration row itself proves recording completion.
