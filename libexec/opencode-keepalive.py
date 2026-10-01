#!/usr/bin/python3
"""Manual OpenCode V2 location heartbeats, without prompts or model calls."""
import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from urllib.parse import urlsplit

TITLE = 'Funk OpenCode keepalive (no prompts)'
OWNER_KEY = 'funk.opencode-keepalive'
OWNER = 'io.arthack.funk.opencode-keepalive.v1'
API_TIMEOUT = 30


class KeepaliveError(Exception):
    def __init__(self, message, transient=False):
        super().__init__(message)
        self.transient = transient


def log(message, error=False):
    print('opencode-keepalive: ' + message,
          file=sys.stderr if error else sys.stdout, flush=True)


def interval(value):
    try:
        seconds = float(value)
    except ValueError:
        seconds = float('nan')
    if not math.isfinite(seconds) or not 0 < seconds <= 1800:
        raise argparse.ArgumentTypeError('interval must be finite and greater than 0, at most 1800 seconds')
    return seconds


def server_url(value):
    try:
        url = urlsplit(value)
        valid = (url.scheme in ('http', 'https') and url.hostname and url.port != 0
                 and url.username is None and url.password is None and not url.query and not url.fragment
                 and not any(c.isspace() or ord(c) < 32 for c in value))
    except ValueError:
        valid = False
    if not valid:
        raise argparse.ArgumentTypeError('server must be an HTTP(S) URL without credentials, query or fragment')
    return value


class API:
    def __init__(self, executable, server):
        self.command = [executable, 'api']
        if server:
            self.command += ['--server', server]

    def request(self, method, path, payload=None, missing_id=None):
        command = self.command + [method.lower(), path]
        if payload is not None:
            command += ['--data', json.dumps(payload)]
        label = f'{method} {path}'
        try:
            result = subprocess.run(command, capture_output=True, text=True,
                                    encoding='utf-8', errors='replace', timeout=API_TIMEOUT)
        except subprocess.TimeoutExpired:
            raise KeepaliveError(f'{label} timed out after {API_TIMEOUT}s; outcome may be unknown', transient=True)
        except OSError as error:
            # In particular, do not keep spawning on process exhaustion (EAGAIN).
            raise KeepaliveError(f'cannot launch opencode (OS error {error.errno}); check PATH/process capacity')

        try:
            body = json.loads(result.stdout) if result.stdout.strip() else None
        except ValueError:
            body = None
        status_match = re.search(r'^HTTP ([0-9]{3})(?: |$)', result.stderr, re.MULTILINE)
        status = int(status_match.group(1)) if status_match else None
        if result.returncode:
            # Only this independently typed 404 proves absence. A CLI/transport
            # failure must never be treated as permission to create a session.
            if (missing_id and status == 404 and isinstance(body, dict)
                    and body.get('_tag') == 'SessionNotFoundError'
                    and body.get('sessionID') == missing_id):
                return None
            detail = f'HTTP {status}' if status else f'CLI exit {result.returncode}'
            raise KeepaliveError(f'{label} failed ({detail}); check the OpenCode CLI/server connection',
                                 transient=status is None or status in (408, 429) or status >= 500)
        if method == 'PATCH':
            if result.stdout.strip():
                raise KeepaliveError(f'{label} returned an unsupported response; expected 204/empty body')
        elif body is None:
            raise KeepaliveError(f'{label} returned empty or malformed JSON')
        # Never echo API bodies or CLI stderr: either may contain secrets.
        return body


def loaded_directories(body):
    if not isinstance(body, list):
        raise KeepaliveError('unsupported loaded-location response; expected a raw JSON array')
    directories = []
    for ref in body:
        if (not isinstance(ref, dict) or set(ref) != {'directory'}
                or not isinstance(ref['directory'], str) or not ref['directory'].startswith('/')
                or '\0' in ref['directory']):
            raise KeepaliveError('unsupported location ref; require an absolute directory only '
                                 '(remote/workspace refs are not silently collapsed)')
        try:
            ref['directory'].encode('utf-8')
        except UnicodeError:
            raise KeepaliveError('unsupported location ref; directory must be valid UTF-8')
        directories.append(ref['directory'])
    # Do not realpath or group by Git project: worktrees are separate locations.
    return list(dict.fromkeys(directories))


def session_id(directory):
    # OpenCode V2 IDs only require the "ses" prefix. This stable namespace plus
    # explicit create ID survives lost responses, retries and independent runners.
    digest = hashlib.sha256((OWNER + '\0' + directory).encode('utf-8')).hexdigest()
    return 'ses_funk_keepalive_v1_' + digest


def owned_session(body, identifier, directory):
    info = body.get('data') if isinstance(body, dict) else None
    if (not isinstance(info, dict) or info.get('id') != identifier
            or info.get('location') != {'directory': directory}
            or not isinstance(info.get('metadata'), dict)
            or info['metadata'].get(OWNER_KEY) != OWNER or info.get('title') != TITLE):
        raise KeepaliveError('refusing session: ID, exact location, ownership marker or fixed title differs')
    return info


def sweep(api, dry_run):
    directories = loaded_directories(api.request('GET', '/api/debug/location'))
    if not directories:
        log('No loaded locations on the selected server; no locations heartbeated. '
            'If OpenCode has active work, check --server URL.')
        return
    for directory in directories:
        identifier = session_id(directory)
        path = '/api/session/' + identifier
        body = api.request('GET', path, missing_id=identifier)
        if body is not None:
            owned_session(body, identifier, directory)
        if dry_run:
            action = 'create/reuse and PATCH' if body is None else 'PATCH'
            log(f'Would {action} {identifier} with fixed nonempty title for {json.dumps(directory)}')
            continue
        if body is None:
            body = api.request('POST', '/api/session', {
                'id': identifier, 'title': TITLE, 'location': {'directory': directory},
                'metadata': {OWNER_KEY: OWNER},
            })
            # Creation may return a pre-existing ID (including a foreign one).
            owned_session(body, identifier, directory)
        api.request('PATCH', path, {'title': TITLE})
        log(f'Heartbeat confirmed for {json.dumps(directory)}')
    if not dry_run:
        log(f'Heartbeat sweep complete: {len(directories)} loaded location(s) refreshed.')


@contextmanager
def runner_lock():
    # No session index or credentials are stored locally; just a stable lock
    # inode. Never unlink it: another runner could already hold the old inode.
    state = Path.home() / '.local/state/funk/opencode-keepalive'
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd = os.open(state / 'runner.lock', os.O_CREAT | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise KeepaliveError('another keepalive runner holds the local lock; stop it before starting another')
        yield
    finally:
        os.close(fd)


def run(api, args):
    log('Server selection: ' + (json.dumps(args.server) if args.server else
                              'OpenCode CLI discovery (use --server URL for another server).'))
    if args.dry_run:
        log('Dry run: one read-only sweep; no local state writes, heartbeat or idle-eviction protection.')
        sweep(api, True)
        return 0
    with runner_lock():
        if not args.once:
            log(f'Foreground watcher; interval {args.interval:g}s. Ctrl-C stops further heartbeats. '
                'All loaded locations will be retained while heartbeats succeed.')
        while True:
            started = time.monotonic()
            try:
                sweep(api, False)
            except KeepaliveError as error:
                log(str(error), error=True)
                log('Sweep incomplete; not all loaded locations have a confirmed heartbeat.', error=True)
                if args.once or not error.transient:
                    return 1
                delay = min(args.interval, 30)
                log(f'Transient failure; will rescan/retry in {delay:g}s. Protection is not assured.', error=True)
            else:
                if args.once:
                    return 0
                delay = max(0, args.interval - (time.monotonic() - started))
            time.sleep(delay)


def main():
    parser = argparse.ArgumentParser(prog='funk opencode-keepalive', description=__doc__)
    parser.add_argument('--once', action='store_true', help='perform one heartbeat sweep and exit')
    parser.add_argument('--dry-run', action='store_true', help='perform one read-only sweep; never heartbeat')
    parser.add_argument('--interval', type=interval, default=1200, metavar='SECONDS',
                        help='seconds between sweeps, greater than 0 and at most 1800 (default: 1200)')
    parser.add_argument('--server', type=server_url, metavar='URL', help='forward an explicit server to every opencode API call')
    args = parser.parse_args()
    executable = shutil.which('opencode')
    if not executable:
        log('opencode is not on PATH; AgentStart owns its installation.', error=True)
        return 1
    os.umask(0o077)
    try:
        return run(API(executable, args.server), args)
    except KeyboardInterrupt:
        log('Stopped; no further heartbeats. Owned sessions remain; normal idle eviction resumes.')
        return 130
    except KeepaliveError as error:
        log(str(error), error=True)
        return 1
    except OSError as error:
        log(f'cannot use the local runner lock (OS error {error.errno}); no watcher started', error=True)
        return 1


if __name__ == '__main__':
    sys.exit(main())
