#!/usr/bin/python3
"""Temporary OpenCode V2 keepalive: one owned session per loaded directory.

Run outside OpenCode-owned shells. Rescans every 20 minutes until Ctrl-C;
keeps all loaded locations resident, including worktrees, without model calls.
Scans the shared service AND this user's private CLI servers on macOS.
Private API passwords are read from those processes, used only in memory,
and never printed or saved. --server limits scanning to an explicit server.
API failures stop the script; rerunning reuses the same sessions.
"""
import argparse
import ctypes
import errno
import hashlib
import json
import os
import re
import subprocess
import sys
import time

TITLE = 'Funk OpenCode keepalive (no prompts)'
OWNER_KEY = 'funk.opencode-keepalive'
OWNER = 'io.arthack.funk.opencode-keepalive.v1'


def api(command, method, path, payload=None, missing_id=None, env=None):
    argv = command + [method, path]
    if payload is not None:
        argv += ['--data', json.dumps(payload)]
    try:
        result = subprocess.run(argv, env=env, capture_output=True, text=True, timeout=30)
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


def private_servers():
    if sys.platform != 'darwin':
        return
    # macOS KERN_PROCARGS2: inspect only same-user OpenCode CLI binaries.
    # Decode argv and the one required API password, not unrelated env values.
    libc = ctypes.CDLL(None, use_errno=True)
    libc.sysctl.argtypes = [ctypes.POINTER(ctypes.c_int), ctypes.c_uint,
                           ctypes.c_void_p, ctypes.POINTER(ctypes.c_size_t),
                           ctypes.c_void_p, ctypes.c_size_t]

    def sysctl(mib, size):
        key = (ctypes.c_int * len(mib))(*mib)
        buffer = ctypes.create_string_buffer(size)
        length = ctypes.c_size_t(size)
        if libc.sysctl(key, len(mib), buffer, ctypes.byref(length), None, 0):
            raise OSError(ctypes.get_errno(), 'cannot inspect OpenCode process')
        return buffer.raw[:length.value]

    maxargs = int.from_bytes(sysctl([1, 8], 4), sys.byteorder)
    rows = subprocess.run(['/bin/ps', '-axo', 'uid=,pid=,comm='], capture_output=True,
                          text=True, timeout=10, check=True).stdout
    for row in rows.splitlines():
        uid, pid, executable = row.strip().split(None, 2)
        if int(uid) != os.getuid() or not executable.endswith('/@opencode/cli/bin/opencode.exe'):
            continue
        pid = int(pid)
        try:
            data = sysctl([1, 49, pid], maxargs)
        except OSError as error:
            if error.errno == errno.ESRCH:  # Process exited during discovery.
                continue
            raise
        argc = int.from_bytes(data[:4], sys.byteorder)
        end = data.index(b'\0', 4)
        if data[4:end] != os.fsencode(executable):  # PID was reused or executable changed.
            continue
        pos = end + 1  # Skip the executable path and padding.
        while pos < len(data) and data[pos] == 0:
            pos += 1
        argv = []
        for _ in range(argc):
            end = data.index(b'\0', pos)
            argv.append(data[pos:end])
            pos = end + 1
        if len(argv) < 2 or argv[1] != b'serve' or b'--stdio' not in argv[2:]:
            continue
        password = next((entry.split(b'=', 1)[1].decode() for entry in data[pos:].split(b'\0')
                         if entry.startswith(b'OPENCODE_PASSWORD=')), None)
        if not password:
            raise RuntimeError(f'private OpenCode server PID {pid} has no readable API credential')
        listeners = subprocess.run(['/usr/sbin/lsof', '-nP', '-a', '-p', str(pid),
                                    '-iTCP', '-sTCP:LISTEN', '-Fn'], capture_output=True,
                                   text=True, timeout=10)
        urls = ['http://' + line[1:] for line in listeners.stdout.splitlines()
                if re.fullmatch(r'n127\.0\.0\.1:[0-9]+', line)]
        if not urls:
            raise RuntimeError(f'private OpenCode server PID {pid} has no discoverable loopback API')
        command = ['opencode', 'api', '--server', urls[0]]
        env = dict(os.environ, OPENCODE_PASSWORD=password)
        info = api(command, 'get', '/api/info', env=env)
        if not isinstance(info, dict) or info.get('pid') != pid:
            raise RuntimeError(f'private OpenCode server PID {pid} changed during discovery')
        yield f'private server PID {pid}', command, env


def check_owned(body, identifier, directory):
    info = body.get('data') if isinstance(body, dict) else None
    if (not isinstance(info, dict) or info.get('id') != identifier
            or info.get('location') != {'directory': directory} or info.get('title') != TITLE
            or not isinstance(info.get('metadata'), dict)
            or info['metadata'].get(OWNER_KEY) != OWNER):
        raise RuntimeError('refusing to modify a session with different ownership, location or title')


def sweep(command, dry_run, env=None):
    locations = api(command, 'get', '/api/debug/location', env=env)
    if (not isinstance(locations, list) or any(
            not isinstance(ref, dict) or set(ref) != {'directory'}
            or not isinstance(ref['directory'], str) or not ref['directory'].startswith('/')
            or '\0' in ref['directory'] for ref in locations)):
        raise RuntimeError('unsupported loaded-location response; expected directory-only refs')
    directories = dict.fromkeys(ref['directory'] for ref in locations)
    refreshed = 0
    for directory in directories:
        if not os.path.isdir(directory):
            print('Skipping removed directory: ' + json.dumps(directory), flush=True)
            continue
        # Explicit stable IDs avoid duplicates on reruns, concurrent creates or lost replies.
        digest = hashlib.sha256((OWNER + '\0' + directory).encode()).hexdigest()
        identifier = 'ses_funk_keepalive_v1_' + digest
        path = '/api/session/' + identifier
        body = api(command, 'get', path, missing_id=identifier, env=env)
        if body is not None:
            check_owned(body, identifier, directory)
        if dry_run:
            print('Would keep alive: ' + json.dumps(directory), flush=True)
            refreshed += 1
            continue
        if body is None:
            body = api(command, 'post', '/api/session', {
                'id': identifier, 'title': TITLE, 'location': {'directory': directory},
                'metadata': {OWNER_KEY: OWNER},
            }, env=env)
            check_owned(body, identifier, directory)
        # A same-title rename emits the durable location event that resets the idle timer.
        api(command, 'patch', path, {'title': TITLE}, env=env)
        print('Kept alive: ' + json.dumps(directory), flush=True)
        refreshed += 1
    return refreshed


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
            servers = [('explicit server' if args.server else 'shared service', command, None)]
            if not args.server:
                servers.extend(private_servers())
            refreshed = 0
            for label, connection, env in servers:
                print(f'Scanning {label}...', flush=True)
                refreshed += sweep(connection, args.dry_run, env)
            if not refreshed:
                print('No loaded locations; nothing protected.', flush=True)
            if args.once or args.dry_run:
                return 0
            time.sleep(max(0, args.interval - (time.monotonic() - started)))
    except KeyboardInterrupt:
        print('\nStopped; keepalive sessions remain for reuse. Normal idle eviction resumes.')
        return 130
    except (RuntimeError, OSError, ValueError, subprocess.SubprocessError) as error:
        print(f'opencode-keepalive: {error}; stopped, protection is not assured.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
