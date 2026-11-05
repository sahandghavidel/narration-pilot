#!/usr/bin/env python3
"""Use the maintained Narration Pilot session runner without duplicating it."""
import os
from pathlib import Path
import sys

repo = Path(os.environ.get('NARRATION_PILOT_REPO', '/Users/sahand/Desktop/projects-test/narration-pilot'))
helper = repo / 'scripts/guided-session.py'
if not helper.is_file():
    raise SystemExit('Narration Pilot helper missing. Set NARRATION_PILOT_REPO to the existing checkout; do not install or rebuild the app implicitly.')
os.execv(sys.executable, [sys.executable, str(helper), *sys.argv[1:]])
