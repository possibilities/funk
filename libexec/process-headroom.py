#!/usr/bin/python3
"""One fork-free macOS process sample and optional AgentNotify socket warning."""
import argparse
import collections
import ctypes as C
import datetime
import json
import os
from pathlib import Path
import socket
import sys
import time
import uuid

LABEL = 'io.arthack.funk.warn-process-headroom'


class BSDInfo(C.Structure):
    _fields_ = [(n, C.c_uint32) for n in (
        'flags', 'status', 'xstatus', 'pid', 'ppid', 'uid', 'gid', 'ruid',
        'rgid', 'svuid', 'svgid', 'rfu')]
    _fields_ += [('comm', C.c_char * 16), ('name', C.c_char * 32)]
    _fields_ += [(n, C.c_uint32) for n in ('nfiles', 'pgid', 'pjobc', 'e_tdev', 'e_tpgid')]
    _fields_ += [('nice', C.c_int32), ('start_sec', C.c_uint64), ('start_usec', C.c_uint64)]


def sample():
    lib = C.CDLL('/usr/lib/libproc.dylib', use_errno=True)
    libc = C.CDLL('/usr/lib/libSystem.B.dylib', use_errno=True)
    lib.proc_listpids.argtypes = [C.c_uint32, C.c_uint32, C.c_void_p, C.c_int]
    lib.proc_pidinfo.argtypes = [C.c_int, C.c_int, C.c_uint64, C.c_void_p, C.c_int]
    libc.sysctlbyname.argtypes = [C.c_char_p, C.c_void_p, C.POINTER(C.c_size_t), C.c_void_p, C.c_size_t]
    def limit(name):
        value, size = C.c_int(), C.c_size_t(C.sizeof(C.c_int))
        if libc.sysctlbyname(name.encode(), C.byref(value), C.byref(size), None, 0):
            raise OSError(C.get_errno(), name)
        return value.value
    user_limit, system_limit = limit('kern.maxprocperuid'), limit('kern.maxproc')
    pids = (C.c_int * (system_limit + 1024))()
    size = lib.proc_listpids(1, 0, pids, C.sizeof(pids))
    if size <= 0 or size >= C.sizeof(pids):
        raise RuntimeError('Cannot obtain a complete process list')
    rows, unreadable = [], 0
    listed = [p for p in pids[:size // C.sizeof(C.c_int)] if p > 0]
    user_size = lib.proc_listpids(4, os.getuid(), pids, C.sizeof(pids))
    if user_size <= 0 or user_size >= C.sizeof(pids):
        raise RuntimeError('Cannot obtain a complete user process list')
    user_pids = [p for p in pids[:user_size // C.sizeof(C.c_int)] if p > 0]
    for pid in user_pids:
        info = BSDInfo()
        if lib.proc_pidinfo(pid, 3, 0, C.byref(info), C.sizeof(info)) != C.sizeof(info):
            unreadable += 1  # Includes processes exiting during the sample.
            continue
        rows.append({'pid': pid, 'ppid': info.ppid, 'uid': info.uid,
                     'name': (info.name or info.comm).decode(errors='replace')})
    owned = [r for r in rows if r['uid'] == os.getuid()]
    by_pid = {r['pid']: r for r in rows}
    # The kernel filters by UID; unreadable detail records remain counted.
    user_headroom = user_limit - len(user_pids)
    system_headroom = system_limit - len(listed)
    return {'sampled_at': time.time(), 'user_processes': len(user_pids),
            'system_processes': len(listed), 'unreadable_pids': unreadable,
            'user_limit': user_limit, 'system_limit': system_limit,
            'user_headroom': user_headroom,
            'system_headroom': system_headroom,
            'headroom': min(user_headroom, system_headroom),
            'largest_user_parents': [dict(pid=p, children=n, name=by_pid.get(p, {}).get('name', 'unknown'))
                for p, n in collections.Counter(r['ppid'] for r in owned).most_common(10)]}


def read_json(path, default):
    return json.loads(path.read_text()) if path.exists() else default


def write_json(path, value):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    temporary.replace(path)


def severity(headroom, previous=0):
    if headroom <= 150:
        return 2
    if headroom <= 300 or (previous and headroom < 400):
        return 1
    return 0


def notify(socket_path, params):
    request = {'id': params['requestId'], 'method': 'send', 'params': params}
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(3)
        connection.connect(str(socket_path))
        connection.sendall(json.dumps(request).encode() + b'\n')
        response = b''
        while b'\n' not in response:
            block = connection.recv(65536)
            if not block or len(response) + len(block) > 1048576:
                raise RuntimeError('Invalid AgentNotify response')
            response += block
    result = json.loads(response.split(b'\n', 1)[0])
    if result.get('id') != params['requestId'] or not result.get('ok'):
        raise RuntimeError('AgentNotify rejected warning: ' + str(result.get('error')))
    return result.get('data')


def check(state_dir, snapshot, sender=notify, now=None):
    now = time.time() if now is None else now
    state_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    state = read_json(state_dir / 'state.json', {})
    context = read_json(state_dir / 'context.json', {})
    level = severity(snapshot['headroom'], state.get('level', 0))
    write_json(state_dir / 'latest.json', snapshot)
    handoff = state_dir / 'resume.md'
    handoff.write_text('# Process headroom warning\n\n'
        'This checker runs every five minutes without inference or child processes.\n'
        'It never kills processes, starts an agent, or restarts a service.\n\n'
        'Sample: ' + datetime.datetime.fromtimestamp(snapshot['sampled_at']).astimezone().isoformat() + '\n\n'
        '## Latest process evidence\n\n```json\n' + json.dumps(snapshot, indent=2) + '\n```\n\n'
        '## Investigation resume metadata\n\n```json\n' + json.dumps(context, indent=2) + '\n```\n\n'
        'Resume manually when there is sufficient headroom. If process creation fails, stop retrying.\n'
        'Session metadata identifies the investigation; it does not authorize stopping other work.\n')
    due = level and (level > state.get('level', 0) or now - state.get('last_sent', 0) >= 1800)
    if not level:
        state.pop('pending', None)
        state['level'] = 0
    elif due or state.get('pending'):
        # Persist the exact request before sending: a lost response can be retried
        # at the next scheduled check with the same idempotency key and payload.
        if not state.get('pending') or level > state.get('pending_level', 0):
            state['pending'] = {
                'requestId': str(uuid.uuid4()), 'group': LABEL,
                'title': 'Process capacity critical' if level == 2 else 'Process capacity running low',
                'message': f"{snapshot['headroom']} process slots remain. "
                    f"User: {snapshot['user_processes']}/{snapshot['user_limit']}; "
                    f"system: {snapshot['system_processes']}/{snapshot['system_limit']}. "
                    'Open for the process snapshot and investigation resume details. '
                    f"Session: {context.get('session_id', 'see handoff')}; cwd: {context.get('cwd', 'see handoff')}.",
                'open': handoff.as_uri()}
            state['pending_level'] = level
        write_json(state_dir / 'state.json', state)
        socket_path = Path(context.get('notify_socket', str(Path.home() / '.local/state/agentnotify/notify.sock')))
        sender(socket_path, state['pending'])
        state['last_sent'] = now
        state['level'] = state.pop('pending_level')
        state.pop('pending')
    write_json(state_dir / 'state.json', state)
    return {'level': level, 'headroom': snapshot['headroom'], 'handoff': str(handoff)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--state-dir', type=Path, default=Path.home() / '.local/state/funk/process-headroom')
    parser.add_argument('--sample-only', action='store_true')
    args = parser.parse_args()
    os.umask(0o077)
    snapshot = sample()
    if args.sample_only:
        print(json.dumps(snapshot, indent=2))
    else:
        check(args.state_dir.resolve(), snapshot)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('process-headroom: ' + str(error), file=sys.stderr)
        sys.exit(1)
