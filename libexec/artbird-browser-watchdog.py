#!/usr/bin/python3
"""Sample Artbird browser pressure and send sustained AgentNotify warnings."""

import argparse
import datetime
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import time
import uuid


LABEL = 'io.arthack.funk.watch-artbird'
MAX_OUTPUT_BYTES = 1024 * 1024
REMOTE_PROBE = r'''
import glob
import json
from pathlib import Path
import subprocess

temperatures = []
for path_text in glob.glob('/sys/class/hwmon/hwmon*/temp*_input'):
    path = Path(path_text)
    try:
        value = int(path.read_text().strip()) / 1000
        name = (path.parent / 'name').read_text().strip()
        label_path = path.with_name(path.name.replace('_input', '_label'))
        label = label_path.read_text().strip() if label_path.exists() else path.stem
        temperatures.append({'sensor': name, 'label': label, 'celsius': value})
    except (OSError, UnicodeError, ValueError):
        continue

process = subprocess.run(
    ['ps', '-eo', 'pid=,ppid=,etimes=,pcpu=,pmem=,comm=', '--sort=-pcpu'],
    check=True, capture_output=True, text=True, timeout=5,
)
rows = []
for line in process.stdout.splitlines():
    fields = line.split(None, 5)
    if len(fields) != 6:
        continue
    try:
        rows.append({
            'pid': int(fields[0]), 'ppid': int(fields[1]), 'elapsed_seconds': int(fields[2]),
            'cpu_percent': float(fields[3]), 'memory_percent': float(fields[4]),
            'command': fields[5],
        })
    except ValueError:
        continue

print(json.dumps({
    'temperatures': temperatures,
    'max_temperature_celsius': max((item['celsius'] for item in temperatures), default=None),
    'load_average': list(__import__('os').getloadavg()),
    # Linux comm names may be truncated to 15 bytes, so match the stable
    # executable prefixes rather than one presentation width.
    'browser_hypervisors': [item for item in rows
                            if item['command'].startswith(('cloud-hyperviso', 'qemu-system'))],
    'top_processes': rows[:10],
}))
'''


def read_json(path, default):
    return json.loads(path.read_text()) if path.exists() else default


def write_json(path, value):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    temporary.replace(path)


def run_json(argv, input_text=None, timeout=20):
    completed = subprocess.run(
        argv, input=input_text, capture_output=True, text=True, timeout=timeout, check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip().splitlines()[-1:] or [f'exit {completed.returncode}']
        raise RuntimeError(f'{Path(argv[0]).name}: {detail[0][:300]}')
    if len(completed.stdout.encode()) > MAX_OUTPUT_BYTES:
        raise RuntimeError(f'{Path(argv[0]).name}: output exceeded {MAX_OUTPUT_BYTES} bytes')
    try:
        return json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError(f'{Path(argv[0]).name}: invalid JSON output') from error


def envelope_data(value, label):
    if not isinstance(value, dict) or value.get('ok') is not True or 'data' not in value:
        raise RuntimeError(f'{label}: unsuccessful or malformed response')
    return value['data']


def sample(host='artbird', ssh_bin='/usr/bin/ssh', agentbrowse_bin=None, now=None):
    now = time.time() if now is None else now
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,127}', host):
        raise ValueError('host must be a bare SSH host name')
    agentbrowse_bin = agentbrowse_bin or str(Path.home() / '.local/bin/agentbrowse')
    snapshot = {'sampled_at': now, 'host': host, 'remote': None,
                'browsers': [], 'sessions': [], 'errors': []}
    try:
        snapshot['remote'] = run_json([
            ssh_bin, '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10',
            '-o', 'ConnectionAttempts=1', host, 'python3', '-'
        ], input_text=REMOTE_PROBE, timeout=20)
    except (OSError, subprocess.SubprocessError, RuntimeError) as error:
        snapshot['errors'].append({'source': 'ssh', 'message': str(error)[:400]})
    try:
        inventory = envelope_data(
            run_json([agentbrowse_bin, 'list', '--json']), 'agentbrowse list')
        if not isinstance(inventory, dict) or not isinstance(inventory.get('browsers'), list):
            raise RuntimeError('agentbrowse list: malformed browser inventory')
        snapshot['browsers'] = inventory['browsers']
        sessions = envelope_data(
            run_json([agentbrowse_bin, 'session', 'list', '--json']),
            'agentbrowse session list')
        if not isinstance(sessions, list):
            raise RuntimeError('agentbrowse session list: malformed session inventory')
        snapshot['sessions'] = sessions
    except (OSError, subprocess.SubprocessError, RuntimeError) as error:
        snapshot['errors'].append({'source': 'agentbrowse', 'message': str(error)[:400]})
    return snapshot


def evaluate(snapshot):
    reasons = []
    level = 0
    required_streak = 1

    def add(code, message, problem_level=1, streak=2):
        nonlocal level, required_streak
        reasons.append({'code': code, 'message': message})
        if problem_level > level:
            level, required_streak = problem_level, streak
        elif problem_level == level:
            required_streak = min(required_streak, streak)

    remote = snapshot.get('remote')
    if isinstance(remote, dict):
        temperature = remote.get('max_temperature_celsius')
        if isinstance(temperature, (int, float)):
            if temperature >= 90:
                add('temperature_critical', f'Artbird reached {temperature:.1f}°C', 2, 1)
            elif temperature >= 80:
                add('temperature_hot', f'Artbird reached {temperature:.1f}°C', 1, 2)
        hypervisors = remote.get('browser_hypervisors', [])
        hottest = max((item.get('cpu_percent', 0) for item in hypervisors
                       if isinstance(item, dict)), default=0)
        if hottest >= 150:
            add('browser_cpu_critical', f'a browser VM is using {hottest:.1f}% CPU', 2, 1)
        elif hottest >= 75:
            add('browser_cpu_high', f'a browser VM is using {hottest:.1f}% CPU', 1, 2)
        if hypervisors and not snapshot.get('browsers'):
            add('untracked_browser_vm', 'browser VM processes exist without AgentBrowse targets', 1, 2)

    bad_targets = [item for item in snapshot.get('browsers', [])
                   if isinstance(item, dict)
                   and (item.get('slot_conflict') is True
                        or str(item.get('state', '')).lower() in {'unknown', 'error', 'failed'})]
    if bad_targets:
        names = ', '.join(str(item.get('name', 'unnamed')) for item in bad_targets[:3])
        add('unhealthy_targets', f'{len(bad_targets)} unhealthy AgentBrowse target(s): {names}', 1, 3)
    if snapshot.get('errors'):
        sources = ', '.join(sorted({str(item.get('source')) for item in snapshot['errors']}))
        add('observation_failed', f'watchdog observation failed: {sources}', 1, 3)

    return {'level': level, 'required_streak': required_streak, 'reasons': reasons,
            'signature': ','.join(sorted(item['code'] for item in reasons))}


def notify(socket_path, params):
    request = {'id': params['requestId'], 'method': 'send', 'params': params}
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(3)
        connection.connect(str(socket_path))
        connection.sendall(json.dumps(request).encode() + b'\n')
        response = b''
        while b'\n' not in response:
            block = connection.recv(65536)
            if not block or len(response) + len(block) > MAX_OUTPUT_BYTES:
                raise RuntimeError('Invalid AgentNotify response')
            response += block
    result = json.loads(response.split(b'\n', 1)[0])
    if result.get('id') != params['requestId'] or not result.get('ok'):
        raise RuntimeError('AgentNotify rejected warning: ' + str(result.get('error')))
    return result.get('data')


def notification_payload(finding, snapshot, handoff, recovery=False):
    request = {
        'requestId': str(uuid.uuid4()), 'group': LABEL, 'open': handoff.as_uri(),
    }
    if recovery:
        request.update({
            'title': 'Artbird browser pressure recovered',
            'message': 'Two healthy checks followed the last warning. No browser process was killed. '
                       'Open for the latest evidence.',
        })
        return request
    remote = snapshot.get('remote') or {}
    temperature = remote.get('max_temperature_celsius')
    hypervisors = remote.get('browser_hypervisors') or []
    hottest = max((item.get('cpu_percent', 0) for item in hypervisors
                   if isinstance(item, dict)), default=0)
    summary = '; '.join(item['message'] for item in finding['reasons'][:3])
    request.update({
        'title': 'Artbird browser pressure critical' if finding['level'] == 2
                 else 'Artbird browser pressure warning',
        'message': f'{summary}. Temperature: {temperature if temperature is not None else "unknown"}°C; '
                   f'VM CPU peak: {hottest:.1f}%; targets: {len(snapshot.get("browsers", []))}. '
                   'Open for bounded evidence; the watchdog takes no corrective action.',
    })
    return request


def write_handoff(path, snapshot, finding):
    sampled = datetime.datetime.fromtimestamp(snapshot['sampled_at']).astimezone().isoformat()
    path.write_text(
        '# Artbird browser watchdog\n\n'
        'This read-only checker runs every five minutes. It never destroys a browser, kills a process, '
        'starts an agent, or restarts a service.\n\n'
        f'Sample: {sampled}\n\n'
        '## Finding\n\n```json\n' + json.dumps(finding, indent=2) + '\n```\n\n'
        '## Latest evidence\n\n```json\n' + json.dumps(snapshot, indent=2) + '\n```\n\n'
        'Investigate with `agentbrowse list --json`, `agentbrowse session list --json`, and read-only '
        '`ssh artbird` process/temperature checks. Preserve persistent profiles and confirm ownership '
        'before releasing a session or stopping a target.\n'
    )


def check(state_dir, snapshot, sender=notify, now=None):
    now = time.time() if now is None else now
    state_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    state = read_json(state_dir / 'state.json', {})
    finding = evaluate(snapshot)
    signature = finding['signature']
    state['streak'] = state.get('streak', 0) + 1 if signature and signature == state.get('signature') else (1 if signature else 0)
    state['signature'] = signature
    state['healthy_streak'] = state.get('healthy_streak', 0) + 1 if finding['level'] == 0 else 0
    write_json(state_dir / 'latest.json', snapshot)
    handoff = state_dir / 'resume.md'
    write_handoff(handoff, snapshot, finding)

    effective = finding['level'] if (finding['level'] == 2 or state['streak'] >= finding['required_streak']) else 0
    pending = state.get('pending')
    if effective:
        due = (not state.get('active_level') or effective > state.get('active_level', 0)
               or signature != state.get('active_signature')
               or now - state.get('last_sent', 0) >= 1800)
        if due and (not pending or pending.get('signature') != signature
                    or pending.get('level', 0) < effective):
            state['pending'] = {'kind': 'alert', 'level': effective, 'signature': signature,
                                'params': notification_payload(finding, snapshot, handoff)}
        if state.get('pending', {}).get('kind') == 'alert':
            write_json(state_dir / 'state.json', state)
            socket_path = Path(state.get('notify_socket', str(Path.home() / '.local/state/agentnotify/notify.sock')))
            sender(socket_path, state['pending']['params'])
            sent = state.pop('pending')
            state['active_level'] = sent['level']
            state['active_signature'] = sent['signature']
            state['last_sent'] = now
    elif finding['level'] == 0:
        if state.get('pending', {}).get('kind') == 'alert':
            state.pop('pending')
        if state.get('active_level') and state['healthy_streak'] >= 2:
            if not state.get('pending'):
                state['pending'] = {'kind': 'recovery',
                                    'params': notification_payload(finding, snapshot, handoff, recovery=True)}
            write_json(state_dir / 'state.json', state)
            socket_path = Path(state.get('notify_socket', str(Path.home() / '.local/state/agentnotify/notify.sock')))
            sender(socket_path, state['pending']['params'])
            state.pop('pending')
            state['active_level'] = 0
            state.pop('active_signature', None)
            state['last_sent'] = now
    write_json(state_dir / 'state.json', state)
    return {'finding': finding, 'streak': state['streak'], 'effective_level': effective,
            'handoff': str(handoff)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', default='artbird')
    parser.add_argument('--state-dir', type=Path,
                        default=Path.home() / '.local/state/funk/artbird-browser-watchdog')
    parser.add_argument('--sample-only', action='store_true')
    args = parser.parse_args()
    os.umask(0o077)
    snapshot = sample(args.host)
    if args.sample_only:
        print(json.dumps({'snapshot': snapshot, 'finding': evaluate(snapshot)}, indent=2))
    else:
        check(args.state_dir.resolve(), snapshot)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('artbird-browser-watchdog: ' + str(error), file=sys.stderr)
        sys.exit(1)
