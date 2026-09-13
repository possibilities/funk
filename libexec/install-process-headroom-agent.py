#!/usr/bin/python3
"""Install only Funk's five-minute, inference-free process warning job."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

LABEL = 'io.arthack.funk.warn-process-headroom'


def render(root, home):
    log = home / 'Library/Logs/Funk/process-headroom.log'
    return {'Label': LABEL, 'FunkInstallerOwner': LABEL + '.v1',
            'ProgramArguments': ['/usr/bin/python3', str(root / 'libexec/process-headroom.py'),
                                 '--state-dir', str(home / '.local/state/funk/process-headroom')],
            'StartInterval': 300, 'RunAtLoad': True, 'ProcessType': 'Background',
            'Umask': 63, 'StandardOutPath': str(log), 'StandardErrorPath': str(log)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--context', type=Path, help='Copy explicit nonsecret investigation metadata into local state')
    args = parser.parse_args()
    if sys.platform != 'darwin' or os.getuid() == 0:
        parser.error('Run as the macOS target user, not root')
    os.umask(0o077)
    root, home = Path(__file__).resolve().parents[1], Path.home()
    payload = render(root, home)
    context = json.loads(args.context.read_text()) if args.context else None
    if context is not None and not isinstance(context, dict):
        parser.error('Context must be a JSON object')
    with tempfile.TemporaryDirectory(prefix='funk-process-headroom-') as raw:
        path = Path(raw) / (LABEL + '.plist')
        path.write_bytes(plistlib.dumps(payload))
        subprocess.run(['/usr/bin/plutil', '-lint', str(path)], check=True)
        if args.check:
            print('Five-minute process warning LaunchAgent validated; no changes.')
            return
        state = home / '.local/state/funk/process-headroom'
        state.mkdir(parents=True, exist_ok=True, mode=0o700)
        if context is not None:
            temporary = state / 'context.tmp'
            temporary.write_text(json.dumps(context, indent=2) + '\n')
            temporary.replace(state / 'context.json')
        subprocess.run([str(root / 'libexec/install-user-launchagent'), LABEL,
                        'com.arthack.funk.warn-process-headroom', str(path),
                        str(home / 'Library/Logs/Funk')], check=True)
    print('Installed ' + LABEL + ': every 300 seconds, no inference.')


if __name__ == '__main__':
    main()
