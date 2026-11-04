#!/usr/bin/env python3
"""Exercise the event-before-status publication race without an app or audio."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time
import unittest
import uuid

HELPER = Path(__file__).resolve().parents[1] / 'guided-narration-review.py'


class GuidedReviewWatchCheck(unittest.TestCase):
    def test_event_before_matching_status_is_retried(self):
        with tempfile.TemporaryDirectory(prefix='guided-watch-check-') as folder:
            root = Path(folder)
            (root / 'events').mkdir()
            sid, event_id = str(uuid.uuid4()), str(uuid.uuid4())
            draft = dict(sessionID=sid, revision=1, narration='Fixture narration.')
            event = dict(schemaVersion=1, id=event_id, kind='approveNarration', draft=draft)
            status = dict(schemaVersion=1, appRunning=True, pid=os.getpid(), draft=draft, phase='awaitingDecision')
            (root / 'status.json').write_text(json.dumps(status))
            (root / 'events' / f'{sid}-r1.json').write_text(json.dumps(event))

            def publish_status():
                time.sleep(.3)
                updated = dict(status, decision=event, phase='approved')
                temporary = root / 'status.tmp'
                temporary.write_text(json.dumps(updated))
                temporary.replace(root / 'status.json')

            thread = threading.Thread(target=publish_status)
            thread.start()
            try:
                result = subprocess.run(['python3', str(HELPER), '--directory', str(root), 'watch',
                                         '--session-id', sid, '--revision', '1', '--timeout', '3'],
                                        capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout)['event']['id'], event_id)
            finally:
                thread.join()

    def test_genuinely_older_revision_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix='guided-watch-check-') as folder:
            root = Path(folder)
            (root / 'events').mkdir()
            sid = str(uuid.uuid4())
            event = dict(schemaVersion=1, id=str(uuid.uuid4()), kind='improveNarration',
                         draft=dict(sessionID=sid, revision=1))
            (root / 'events' / f'{sid}-r1.json').write_text(json.dumps(event))
            status = dict(schemaVersion=1, appRunning=True, pid=os.getpid(),
                          draft=dict(sessionID=sid, revision=2), phase='reading')
            (root / 'status.json').write_text(json.dumps(status))
            result = subprocess.run(['python3', str(HELPER), '--directory', str(root), 'watch',
                                     '--session-id', sid, '--revision', '1', '--timeout', '1'],
                                    capture_output=True, text=True, timeout=3)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('older revision', result.stderr)
            self.assertFalse((root / 'commands').exists())


if __name__ == '__main__':
    unittest.main()
