#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
python3 - "${1:-release}" <<'PYTHON'
from pathlib import Path
import plistlib, subprocess, tempfile, time, os
configuration = __import__('sys').argv[1]
assert configuration in ('debug','release'), 'Expected debug or release'
name, executable, identity = ('Narration Pilot', 'NarrationPilot', 'local.clipboardreadermac')
source = Path.cwd()/'.build/app'/configuration/(name+'.app')
with (source/'Contents/Info.plist').open('rb') as f: assert plistlib.load(f)['CFBundleIdentifier']==identity
subprocess.run(['codesign','--verify','--deep','--strict',str(source)],check=True)
stage = Path(tempfile.mkdtemp(prefix='.app-install-',dir='/Applications'))
staged = stage/(name+'.app')
subprocess.run(['ditto',str(source),str(staged)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(staged)],check=True)
backup = Path(tempfile.mkdtemp(prefix='app-install-backup-'))/(name+'.bundle-backup')
installed = Path('/Applications')/(name+'.app')
subprocess.run(['pkill','-x',executable],check=False)
for _ in range(50):
    if subprocess.run(['pgrep','-x',executable],capture_output=True).returncode: break
    time.sleep(0.1)
else: raise RuntimeError('Application did not exit; installed copy has not been replaced')
try:
    if installed.exists(): installed.rename(backup)
    staged.rename(installed)
    subprocess.run(['codesign','--verify','--deep','--strict',str(installed)],check=True)
    assert (source/'Contents/MacOS'/executable).read_bytes()==(installed/'Contents/MacOS'/executable).read_bytes()
except Exception:
    if backup.exists():
        if installed.exists(): installed.rename(stage/(name+'.failed-bundle'))
        backup.rename(installed)
    raise
os.utime(installed,None)
stage.rmdir()
# Refresh the ordinary development app too: stale references will redirect.
if configuration=='release':
    debug = Path.cwd()/'.build/app/debug'/(name+'.app')
    if debug.exists():
        debug.rename(backup.parent/(name+'-debug.bundle-backup'))
        subprocess.run(['ditto',str(installed),str(debug)],check=True)
subprocess.run(['open',str(installed)],check=True)
print('Installed and verified:',installed)
print('Rollback bundle:',backup)
PYTHON
