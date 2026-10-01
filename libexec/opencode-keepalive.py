#!/usr/bin/python3
"""Temporary OpenCode V2 keepalive: one owned session per loaded directory.

Run outside OpenCode-owned shells. Rescans every 20 minutes until Ctrl-C;
keeps all loaded locations resident, including worktrees, without model calls.
Uses the CLI's shared service unless --server selects an authenticated server.
API failures stop the script; rerunning reuses the same sessions.
"""
import argparse
import hashlib
import json
import re
import subprocess
import sys
import time

TITLE = 'Funk OpenCode keepalive (no prompts)'
OWNER_KEY = 'funk.opencode-keepalive'
OWNER = 'io.arthack.funk.opencode-keepalive.v1'


def api(command, method, path, payload=None, missing_id=None):
    argv = command + [method, path]
    if payload is not None:
        argv += ['--data', json.dumps(payload)]
    try:
        result = subprocess.run(argv, capture_output=True, text=True, timeout=30)
    except subprocess.TimeoutExpired:
        raise RuntimeError(f'{method} {path} timed out; outcome may be unknown') from None
    try:
        body = json.loads(result.stdout) if result.stdout.strip() else None
    except ValueError:
        raise RuntimeError(f'{method} {path}: invalid JSON; check the selected server') from None
    if result.returncode:
        # Only a typed session-not-found response permits creation, not a network failure.
        if (missing_id and re.search(r'^HTTP 404(?: |$)', result.stderr, re.MULTILINE)
                and isinstance(body, dict) and body.get('_tag') == 'SessionNotFoundError'
                and body.get('sessionID') == missing_id):
            return None
        # Do not echo response bodies or stderr, which can contain credentials.
        raise RuntimeError(f'{method} {path} failed (CLI exit {result.returncode}); check OpenCode connectivity/authentication')
    if (method != 'patch' and body is None) or (method == 'patch' and result.stdout.strip()):
        raise RuntimeError(f'{method} {path}: unexpected API response')
    return body


def check_owned(body, identifier, directory):
    info = body.get('data') if isinstance(body, dict) else None
    if (not isinstance(info, dict) or info.get('id') != identifier
            or info.get('location') != {'directory': directory} or info.get('title') != TITLE
            or not isinstance(info.get('metadata'), dict)
            or info['metadata'].get(OWNER_KEY) != OWNER):
        raise RuntimeError('refusing to modify a session with different ownership, location or title')


def sweep(command, dry_run):
    locations = api(command, 'get', '/api/debug/location')
    if (not isinstance(locations, list) or any(
            not isinstance(ref, dict) or set(ref) != {'directory'}
            or not isinstance(ref['directory'], str) or not ref['directory'].startswith('/')
            or '\0' in ref['directory'] for ref in locations)):
        raise RuntimeError('unsupported loaded-location response; expected directory-only refs')
    directories = dict.fromkeys(ref['directory'] for ref in locations)
    if not directories:
        print('No loaded locations; nothing protected. Check --server if you have active work.', flush=True)
    for directory in directories:
        # Explicit stable IDs avoid duplicates on reruns, concurrent creates or lost replies.
        digest = hashlib.sha256((OWNER + '\0' + directory).encode()).hexdigest()
        identifier = 'ses_funk_keepalive_v1_' + digest
        path = '/api/session/' + identifier
        body = api(command, 'get', path, missing_id=identifier)
        if body is not None:
            check_owned(body, identifier, directory)
        if dry_run:
            print('Would keep alive: ' + json.dumps(directory), flush=True)
            continue
        if body is None:
            body = api(command, 'post', '/api/session', {
                'id': identifier, 'title': TITLE, 'location': {'directory': directory},
                'metadata': {OWNER_KEY: OWNER},
            })
            check_owned(body, identifier, directory)
        # A same-title rename emits the durable location event that resets the idle timer.
        api(command, 'patch', path, {'title': TITLE})
        print('Kept alive: ' + json.dumps(directory), flush=True)


def main():
    parser = argparse.ArgumentParser(prog='funk opencode-keepalive', description=__doc__)
    parser.add_argument('--once', action='store_true', help='one heartbeat sweep, then exit')
    parser.add_argument('--dry-run', action='store_true', help='one read-only preview; no protection')
    parser.add_argument('--interval', type=int, default=1200, metavar='SECONDS',
                        help='seconds between sweeps, 1–1800 (default: 1200)')
    parser.add_argument('--server', metavar='URL', help='target another OpenCode server using native CLI authentication')
    args = parser.parse_args()
    if not 1 <= args.interval <= 1800:
        parser.error('--interval must be between 1 and 1800 seconds')
    command = ['opencode', 'api'] + (['--server', args.server] if args.server else [])
    if not args.once and not args.dry_run:
        print('Keeping loaded locations alive; Ctrl-C stops. No prompts or model calls.', flush=True)
    try:
        while True:
            started = time.monotonic()
            sweep(command, args.dry_run)
            if args.once or args.dry_run:
                return 0
            time.sleep(max(0, args.interval - (time.monotonic() - started)))
    except KeyboardInterrupt:
        print('\nStopped; keepalive sessions remain for reuse. Normal idle eviction resumes.')
        return 130
    except (RuntimeError, OSError) as error:
        print(f'opencode-keepalive: {error}; stopped, protection is not assured.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
