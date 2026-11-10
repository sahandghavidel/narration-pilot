#!/usr/bin/env python3
"""Active-agent practice bridge. Does not execute screen actions or fake approvals.

Read context once, author a word-anchored action plan and continuity evidence,
arm the real-cursor action runner, then start playback. A/G decisions remain real
user shortcut events. Before recording, restore the same checkpoint and submit a
fresh gate. After actions, report their actual clock times and observed capture.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import sys
import time
import uuid

ROOT = Path.home() / 'Library/Application Support/local.clipboardreadermac/GuidedNarrationReview/Practice'


def load(path):
    return json.loads(path.read_text())


def live(root, session_id=None, run_id=None):
    state = load(root / 'status.json')
    if not state.get('appRunning') or time.time() - (root / 'status.json').stat().st_mtime > 4:
        raise RuntimeError('Practice heartbeat is not running or is stale')
    os.kill(state['pid'], 0)
    if session_id and (state.get('approval') or {}).get('draft', {}).get('sessionID', '').lower() != session_id.lower():
        raise RuntimeError('The requested guided session is no longer current')
    if run_id and (state.get('runID') or '').lower() != run_id.lower():
        raise RuntimeError('Practice attempt changed; stop old actions and restore the original checkpoint')
    return state


def send(root, run_id, kind, **payload):
    state = live(root, run_id=run_id)
    if not state.get('active'):
        raise RuntimeError('No guided practice is active')
    command_id = str(uuid.uuid4())
    command = dict(schemaVersion=1, id=command_id, runID=run_id,
                   sessionID=state['approval']['draft']['sessionID'], kind=kind,
                   createdAt=datetime.now(timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z'), **payload)
    path = root / 'commands' / f'{command_id}.json'
    temporary = path.with_suffix('.tmp')
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as stream:
        json.dump(command, stream, ensure_ascii=False)
    os.replace(temporary, path)
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        receipt = root / 'receipts' / path.name
        if receipt.exists():
            result = load(receipt)
            if not result.get('accepted'):
                raise RuntimeError(result.get('message', 'Practice command rejected'))
            return result
        time.sleep(.025)
    raise RuntimeError('No command receipt. Inspect current practice state before retrying; do not assume playback or recording started.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=ROOT)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('status')
    context = commands.add_parser('context')
    context.add_argument('--run-id', required=True)
    watch = commands.add_parser('watch')
    watch.add_argument('--session-id', required=True)
    watch.add_argument('--kind', choices=['practiceRequested', 'recordRequested', 'practiceReplayRequested', 'manualRestoreRequested', 'recordingCompleted'], required=True)
    watch.add_argument('--after-event-id')
    watch.add_argument('--ack', action='store_true')
    watch.add_argument('--timeout', type=float, default=55)
    for name in ['plan', 'start', 'finish', 'record', 'manual-ready', 'record-finish', 'abort']:
        cmd = commands.add_parser(name)
        cmd.add_argument('--run-id', required=True)
        if name == 'plan': cmd.add_argument('--plan-file', type=Path, required=True)
        if name in ['start', 'record', 'manual-ready']: cmd.add_argument('--gate-file', type=Path, required=True)
        if name in ['finish', 'record-finish']: cmd.add_argument('--results-file', type=Path, required=True)
    args = parser.parse_args()
    root = args.directory
    if args.command == 'status':
        result = live(root)
    elif args.command == 'context':
        state = live(root, run_id=args.run_id)
        context = load(Path(state['contextPath']))
        resolved = []
        for action in (state.get('plan') or {}).get('actions', []):
            seconds = context['words'][action['wordIndex']]['start'] if action.get('wordIndex') is not None else action['atSeconds']
            resolved.append(dict(action, resolvedSeconds=seconds))
        result = dict(runID=state['runID'], attempt=state['attempt'], context=context, resolvedActions=resolved)
    elif args.command == 'watch':
        if not 0 < args.timeout <= 60: raise RuntimeError('Use a bounded watch of at most 60 seconds')
        deadline = time.monotonic() + args.timeout
        expected_phase = {'recordingCompleted': 'completed', 'practiceReplayRequested': 'practiceRequested'}.get(args.kind, args.kind)
        while True:
            state = live(root, session_id=args.session_id)
            event = state.get('pendingEvent') or {}
            if state['phase'] == expected_phase and event.get('kind') == args.kind and event.get('id') != args.after_event_id:
                result = dict(event=event, status=state)
                if args.ack:
                    result['receipt'] = send(root, state['runID'], 'acknowledge', eventID=event['id'])
                break
            if state['phase'] in ['blocked', 'suspended', 'inactive']:
                result = dict(needsAttention=True, status=state)
                break
            if time.monotonic() >= deadline:
                result = dict(waiting=True, status=state)
                break
            time.sleep(.05)
    else:
        state = live(root, run_id=args.run_id)
        payload = {}
        if args.command == 'plan':
            plan = load(args.plan_file)
            context = load(Path(state['contextPath']))
            plan.setdefault('id', str(uuid.uuid4()))
            plan.setdefault('audioVersionID', context['audioVersionID'])
            plan.setdefault('audioSHA256', context['audioSHA256'])
            payload['plan'] = plan
        if args.command in ['start', 'record', 'manual-ready']:
            # A/G notifications are spoken outside playback/capture. Wait for
            # that real transition, then submit the already verified gate.
            deadline = time.monotonic() + 10
            while state.get('promptBusy') and time.monotonic() < deadline:
                time.sleep(.05)
                state = live(root, run_id=args.run_id)
            if state.get('promptBusy'): raise RuntimeError('Spoken prompt is still active; playback/recording was not requested')
            payload['gate'] = load(args.gate_file)
        if args.command in ['finish', 'record-finish']:
            payload['results'] = load(args.results_file)
        kind = {'record-finish': 'recordFinish', 'manual-ready': 'manualReady'}.get(args.command, args.command)
        result = send(root, args.run_id, kind, **payload)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        print(json.dumps(dict(error=str(error))), file=sys.stderr)
        sys.exit(1)
