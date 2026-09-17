#!/usr/bin/python3
"""Install Funk's read-only five-minute Artbird browser watchdog."""

import argparse
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile


LABEL = 'io.arthack.funk.watch-artbird'


def render(root, home, host='artbird'):
    log = home / 'Library/Logs/Funk/artbird-browser-watchdog.log'
    return {
        'Label': LABEL,
        'FunkInstallerOwner': LABEL + '.v1',
        'ProgramArguments': [
            '/usr/bin/python3', str(root / 'libexec/artbird-browser-watchdog.py'),
            '--host', host,
            '--state-dir', str(home / '.local/state/funk/artbird-browser-watchdog'),
        ],
        'StartInterval': 300,
        'RunAtLoad': True,
        'ProcessType': 'Background',
        'Umask': 63,
        'EnvironmentVariables': {
            'HOME': str(home),
            'PATH': f'{home}/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin',
        },
        'StandardOutPath': str(log),
        'StandardErrorPath': str(log),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--host', default='artbird')
    args = parser.parse_args()
    if sys.platform != 'darwin' or os.getuid() == 0:
        parser.error('Run as the macOS target user, not root')
    os.umask(0o077)
    root, home = Path(__file__).resolve().parents[1], Path.home()
    payload = render(root, home, args.host)
    with tempfile.TemporaryDirectory(prefix='funk-artbird-watchdog-') as raw:
        path = Path(raw) / (LABEL + '.plist')
        path.write_bytes(plistlib.dumps(payload))
        subprocess.run(['/usr/bin/plutil', '-lint', str(path)], check=True)
        if args.check:
            print('Five-minute Artbird browser watchdog validated; no changes.')
            return
        subprocess.run([
            str(root / 'libexec/install-user-launchagent'), LABEL,
            'com.arthack.funk.watch-artbird', str(path),
            str(home / 'Library/Logs/Funk'),
        ], check=True)
    print('Installed ' + LABEL + ': every 300 seconds, read-only, no inference.')


if __name__ == '__main__':
    main()
