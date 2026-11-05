#!/usr/bin/env python3
"""Start one reusable AgentCursor runner; prepare scenes before narration review."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone

REPO = Path(__file__).resolve().parents[1]
DEFAULT = Path.home() / 'Library/Application Support/local.clipboardreadermac/GuidedSessionRunner'


def load(path):
    return json.loads(path.read_text())


def current(root):
    state = load(root / 'status.json')
    if not state.get('running') or time.time() - (root / 'status.json').stat().st_mtime > 4:
        raise RuntimeError('Session runner is stopped or stale')
    os.kill(state['pid'], 0)
    return state


def command(root, kind, **payload):
    current(root)
    identity = str(uuid.uuid4())
    value = dict(id=identity, kind=kind, createdAt=datetime.now(timezone.utc).isoformat(), **payload)
    file = root / 'commands' / (identity + '.json')
    temporary = file.with_suffix('.tmp')
    descriptor = os.open(temporary, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(descriptor, 'w') as stream:
        json.dump(value, stream, ensure_ascii=False)
    temporary.replace(file)
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        receipt = root / 'receipts' / file.name
        if receipt.exists():
            response = load(receipt)
            if not response['accepted']: raise RuntimeError(response.get('message', 'Runner command rejected'))
            return response
        time.sleep(.025)
    raise RuntimeError('No runner receipt. Inspect status before retrying.')


def listen_for_chapter_request(review_root):
    """Remain idle across manual takes and scene changes until the app needs the agent."""
    while True:
        status_file = review_root / 'status.json'
        if status_file.exists() and time.time() - status_file.stat().st_mtime < 4:
            review = load(status_file)
            draft = review.get('draft') or {}
            if review.get('appRunning') and review.get('active') and review.get('remainingChapterScenes') is not None:
                decision = review.get('decision') or {}
                if review['phase'] == 'improving' and decision.get('draft') == draft:
                    return dict(request='revise', draft=draft, eventID=decision['id'])
                practice_file = review_root / 'Practice/status.json'
                if review['phase'] == 'audioApproved' and practice_file.exists() and time.time() - practice_file.stat().st_mtime < 4:
                    practice = load(practice_file)
                    approval = practice.get('approval') or {}
                    if practice.get('active') and approval.get('draft') == draft:
                        if practice['phase'] == 'blocked':
                            return dict(request='checkPractice', draft=draft, runID=practice['runID'], message=practice.get('message'))
                        runner_file = review_root.parent / 'GuidedSessionRunner/status.json'
                        if runner_file.exists() and time.time() - runner_file.stat().st_mtime < 4:
                            runner = load(runner_file)
                            event = runner.get('lastEvent') or {}
                            if (runner.get('running') and runner.get('phase') == 'needsAgent'
                                    and runner.get('reason') == 'workflowFailure' and event.get('kind') == 'needsAgent'
                                    and event.get('sessionID') == draft.get('sessionID')
                                    and event.get('runID') == practice.get('runID')):
                                return dict(request='checkPractice', draft=draft, runID=practice['runID'], message=event['message'])
                    if (practice.get('active') and practice['phase'] == 'practiceRequested'
                            and approval.get('draft') == draft
                            and approval.get('id') == (review.get('audioDecision') or {}).get('id')):
                        return dict(request='improvePractice' if practice.get('attempt', 1) > 1 else 'practice', draft=draft, runID=practice['runID'])
        time.sleep(.25)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=DEFAULT)
    sub = parser.add_subparsers(dest='command', required=True)
    start = sub.add_parser('start')
    start.add_argument('--sdk', type=Path)
    start.add_argument('--app-directory', type=Path)
    start.add_argument('--visual', choices=['auto', 'supplied'], default='auto')
    listen = sub.add_parser('listen', help='Stand by through manual scenes until practice or revision is requested')
    listen.add_argument('--review-directory', type=Path, default=DEFAULT.parent / 'GuidedNarrationReview')
    sub.add_parser('status')
    for name in ['prepare', 'update']:
        prepare = sub.add_parser(name)
        if name == 'update': prepare.add_argument('--run-id', help='Current run ID for a practice improvement')
        prepare.add_argument('--scene-file', type=Path, required=True)
    sub.add_parser('resume')
    evidence = sub.add_parser('evidence')
    evidence.add_argument('--request-id', required=True)
    evidence.add_argument('--manifest', type=Path, required=True)
    wait = sub.add_parser('wait')
    wait.add_argument('--timeout', type=float, default=55)
    wait.add_argument('--after-sequence', type=int, default=-1)
    sub.add_parser('stop')
    args = parser.parse_args()
    root = args.directory.resolve()
    if args.command == 'start':
        try:
            result = current(root)
        except (OSError, ValueError, RuntimeError):
            root.mkdir(parents=True, exist_ok=True, mode=0o700)
            # Refuse duplicate workers even if their heartbeat stalled.
            pidfile = root / 'pid'
            if pidfile.exists():
                try:
                    os.kill(int(pidfile.read_text()), 0)
                except (ProcessLookupError, ValueError): pass
                else: raise RuntimeError('An existing runner PID is alive but stale; inspect/stop it before starting another')
            argv = ['node', str(REPO / 'scripts/guided-session-runner.mjs'), '--directory', str(root), '--visual', args.visual]
            if args.sdk: argv += ['--sdk', str(args.sdk.resolve())]
            if args.app_directory: argv += ['--app-directory', str(args.app_directory.resolve())]
            descriptor = os.open(root / 'runner.log', os.O_CREAT | os.O_APPEND | os.O_WRONLY, 0o600)
            with os.fdopen(descriptor, 'a') as stream:
                process = subprocess.Popen(argv, stdout=stream, stderr=stream, start_new_session=True)
            pidfile.write_text(str(process.pid));pidfile.chmod(0o600)
            for _ in range(100):
                try:
                    result = current(root)
                    if result['pid'] == process.pid: break
                except (OSError, ValueError, RuntimeError): pass
                if process.poll() is not None: raise RuntimeError('Runner could not start; inspect runner.log')
                time.sleep(.05)
            else: raise RuntimeError('Runner startup timed out')
    elif args.command == 'listen':
        result = listen_for_chapter_request(args.review_directory)
    elif args.command in ['prepare', 'update']:
        result = command(root, args.command, scene=load(args.scene_file), runID=getattr(args, 'run_id', None))
    elif args.command == 'resume':
        result = command(root, 'resume')
    elif args.command == 'evidence':
        result = command(root, 'evidence', requestID=args.request_id, manifest=load(args.manifest))
    elif args.command == 'stop':
        result = command(root, 'stop')
    elif args.command == 'wait':
        if not 0 < args.timeout <= 60: raise RuntimeError('Use a bounded wait of at most 60 seconds')
        deadline = time.monotonic() + args.timeout
        while True:
            result = current(root)
            if (result.get('sequence', 0) > args.after_sequence
                    and result['phase'] in ['prepared', 'needsEvidence', 'needsAgent', 'sceneComplete']): break
            if time.monotonic() >= deadline:
                result = dict(waiting=True, status=result);break
            time.sleep(.05)
    else:
        result = current(root)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError) as error:
        print(json.dumps(dict(error=str(error))), file=sys.stderr)
        sys.exit(1)
