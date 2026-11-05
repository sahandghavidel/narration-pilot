#!/usr/bin/env python3
"""Local Narration Pilot review handshake; no network, clipboard or app activation.

An active agent submits drafts, waits for A/G events, acknowledges them, and
submits an improved revision in response to the exact improvement event. This
helper does not wake an ended chat or generate narration by itself.
"""
from datetime import datetime, timezone
import argparse
import json
import os
from pathlib import Path
import sys
import time
import uuid

DEFAULT_ROOT = Path.home() / 'Library/Application Support/local.clipboardreadermac/GuidedNarrationReview'


def load(path):
    return json.loads(path.read_text())


def status(root):
    value = load(root / 'status.json')
    if value.get('schemaVersion') != 1:
        raise RuntimeError('Unsupported narration review status schema')
    return value


def ensure_live(root):
    value = status(root)
    if not value.get('appRunning') or time.time() - (root / 'status.json').stat().st_mtime > 4:
        raise RuntimeError('Narration Pilot review is not running or its heartbeat is stale')
    os.kill(value['pid'], 0)
    return value


def send(root, session, kind, draft=None, event_id=None, next_candidate=None):
    ensure_live(root)
    command_id = str(uuid.uuid4())
    command = dict(schemaVersion=1, id=command_id, sessionID=str(uuid.UUID(session)), kind=kind,
                   createdAt=datetime.now(timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z'))
    if draft is not None:
        command['draft'] = draft
    if next_candidate is not None:
        command['nextCandidate'] = next_candidate
    if event_id:
        command['eventID'] = str(uuid.UUID(event_id))
    path = root / 'commands' / (command_id + '.json')
    temporary = path.with_suffix('.tmp')
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as stream:
        json.dump(command, stream, ensure_ascii=False)
    os.replace(temporary, path)
    receipt = root / 'receipts' / path.name
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if receipt.exists():
            result = load(receipt)
            if not result.get('accepted'):
                raise RuntimeError(result.get('message', 'Command rejected'))
            return result
        time.sleep(.05)
    raise RuntimeError('No command receipt yet. Do not assume the draft or decision was received; inspect status.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=DEFAULT_ROOT)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('status')
    submit = commands.add_parser('submit')
    submit.add_argument('--session-id', default=None)
    submit.add_argument('--scene-id', required=True)
    submit.add_argument('--revision', type=int, default=1)
    text = submit.add_mutually_exclusive_group(required=True)
    text.add_argument('--text')
    text.add_argument('--text-file', type=Path)
    submit.add_argument('--event-id', help='Required for a revised draft; exact improvement event ID')
    submit.add_argument('--next-session-id', help='Identity of the next queued scene whose wording needs to follow this revision')
    submit.add_argument('--next-text', help='Replacement candidate to read for normal A/G review at handoff')
    watch = commands.add_parser('watch')
    watch.add_argument('--session-id', required=True)
    watch.add_argument('--revision', type=int, required=True)
    watch.add_argument('--timeout', type=float, default=55)
    watch.add_argument('--ack', action='store_true')
    watch.add_argument('--stage', choices=['narration', 'audio'], default='narration')
    ack = commands.add_parser('acknowledge')
    ack.add_argument('--session-id', required=True)
    ack.add_argument('--event-id', required=True)
    for name in ['replay', 'end', 'generate-audio']:
        command = commands.add_parser(name)
        command.add_argument('--session-id', required=True)
    args = parser.parse_args()
    root = args.directory
    if args.command == 'status':
        result = status(root)
    elif args.command == 'submit':
        session = str(uuid.UUID(args.session_id)) if args.session_id else str(uuid.uuid4())
        narration = args.text if args.text is not None else args.text_file.read_text()
        draft = dict(sessionID=session, sceneID=args.scene_id, revision=args.revision, narration=narration)
        candidate = None
        if args.next_text is not None or args.next_session_id is not None:
            queue = ensure_live(root).get('remainingChapterScenes') or []
            if not args.event_id or not args.next_text or not queue or queue[0]['sessionID'].lower() != (args.next_session_id or '').lower():
                raise RuntimeError('Supply the current revision event and the matching next scene ID and wording')
            candidate = dict(queue[0], narration=args.next_text)
        result = dict(sessionID=session, receipt=send(root, session, 'submit', draft=draft, event_id=args.event_id, next_candidate=candidate), status=status(root))
    elif args.command == 'watch':
        if not 0 < args.timeout <= 60:
            raise RuntimeError('Watch timeout must be between 0 and 60 seconds; resume another bounded watch if needed')
        session = str(uuid.UUID(args.session_id))
        path = root / ('audio-events' if args.stage == 'audio' else 'events') / f'{session.lower()}-r{args.revision}.json'
        deadline = time.monotonic() + args.timeout
        while True:
            current = ensure_live(root)
            if current.get('draft', {}).get('sessionID', '').lower() != session.lower():
                raise RuntimeError('The requested review session is no longer current')
            if path.exists():
                event = load(path)
                if (event.get('schemaVersion') != 1 or event.get('kind') not in (['approveAudio'] if args.stage == 'audio' else ['approveNarration', 'improveNarration'])
                        or event.get('draft', {}).get('revision') != args.revision
                        or event.get('draft', {}).get('sessionID', '').lower() != session.lower()):
                    raise RuntimeError('Invalid decision event')
                # Event files are committed before the status snapshot. Re-read
                # after observing the event, and tolerate that publication gap.
                current = ensure_live(root)
                if (current.get('audioDecision' if args.stage == 'audio' else 'decision') or {}).get('id') == event['id']:
                    result = dict(event=event)
                    if args.ack:
                        result['receipt'] = send(root, session, 'acknowledge', event_id=event['id'])
                    break
                if current.get('draft', {}).get('revision') != args.revision:
                    raise RuntimeError('Decision belongs to an older revision; it was not acknowledged')
                # The matching status may still be in flight. Keep waiting below
                # rather than reporting a stale event or acknowledging the wrong one.
            if time.monotonic() >= deadline:
                result = dict(waiting=True, sessionID=session, revision=args.revision, phase=current['phase'])
                break
            time.sleep(.1)
    elif args.command == 'acknowledge':
        result = send(root, args.session_id, 'acknowledge', event_id=args.event_id)
    else:
        result = send(root, args.session_id, 'generateAudio' if args.command == 'generate-audio' else args.command)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError) as error:
        print(json.dumps(dict(error=str(error))), file=sys.stderr)
        sys.exit(1)
