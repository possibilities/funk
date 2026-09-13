#!/usr/bin/env python3
"""Synthetic pressure and isolated socket checks; never touch the real inbox."""
import importlib.util
import json
from pathlib import Path
import socket
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'libexec' / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


watch = load('watch', 'process-headroom.py')
installer = load('installer', 'install-process-headroom-agent.py')


def sample(headroom):
    return {'sampled_at': 10000, 'headroom': headroom, 'user_processes': 1875-headroom,
            'user_limit': 1875, 'system_processes': 2000-headroom, 'system_limit': 2500}


class Checks(unittest.TestCase):
    def test_thresholds_throttle_escalation_and_recovery(self):
        with tempfile.TemporaryDirectory() as raw:
            state, sent = Path(raw), []
            send = lambda path, params: sent.append(dict(params))
            watch.check(state, sample(700), send, now=10000)
            self.assertEqual(sent, [])
            watch.check(state, sample(300), send, now=10300)
            watch.check(state, sample(220), send, now=10600)
            self.assertEqual(len(sent), 1)
            watch.check(state, sample(150), send, now=10900)
            self.assertEqual(len(sent), 2)
            self.assertEqual(sent[-1]['title'], 'Process capacity critical')
            watch.check(state, sample(120), send, now=12700)
            self.assertEqual(len(sent), 3)
            watch.check(state, sample(399), send, now=13000)
            self.assertEqual(len(sent), 3)
            watch.check(state, sample(400), send, now=13300)
            watch.check(state, sample(300), send, now=13600)
            self.assertEqual(len(sent), 4)
            self.assertEqual(len({s['group'] for s in sent}), 1)
            self.assertTrue((state / 'resume.md').exists())

    def test_failed_delivery_reuses_exact_request_and_recovers(self):
        with tempfile.TemporaryDirectory() as raw:
            state, attempts = Path(raw), []
            def fail(path, params):
                attempts.append(dict(params))
                raise OSError('notifier unavailable')
            with self.assertRaises(OSError):
                watch.check(state, sample(200), fail, now=10000)
            watch.check(state, sample(190), lambda p, v: attempts.append(dict(v)), now=10300)
            self.assertEqual(attempts[0], attempts[1])
            self.assertNotIn('pending', json.loads((state / 'state.json').read_text()))

    def test_recovery_discards_unsent_alert(self):
        with tempfile.TemporaryDirectory() as raw:
            state = Path(raw)
            def fail(*_):
                raise OSError('offline')
            with self.assertRaises(OSError):
                watch.check(state, sample(100), fail, now=10000)
            watch.check(state, sample(600), fail, now=10300)
            self.assertNotIn('pending', json.loads((state / 'state.json').read_text()))

    def test_wire_contract_without_real_notification(self):
        with tempfile.TemporaryDirectory(prefix='pw-', dir='/tmp') as raw:
            path = Path(raw) / 'n.sock'
            seen = []
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
                server.bind(str(path))
                server.listen(1)
                server.settimeout(5)
                def respond():
                    connection, _ = server.accept()
                    with connection:
                        connection.settimeout(5)
                        data = b''
                        while b'\n' not in data:
                            data += connection.recv(4096)
                        frame = json.loads(data)
                        seen.append(frame)
                        connection.sendall(json.dumps({'id': frame['id'], 'ok': True,
                                                       'data': {'id': 'fixture'}}).encode()+b'\n')
                worker = threading.Thread(target=respond)
                worker.start()
                try:
                    self.assertEqual(watch.notify(path, {'requestId':'test', 'message':'fixture'}), {'id':'fixture'})
                finally:
                    worker.join(timeout=6)
                self.assertFalse(worker.is_alive())
            self.assertEqual(seen[0]['method'], 'send')

    def test_launchd_contract(self):
        plist = installer.render(Path('/checkout'), Path('/home/test'))
        self.assertEqual(plist['StartInterval'], 300)
        self.assertTrue(plist['RunAtLoad'])
        self.assertNotIn('KeepAlive', plist)
        self.assertEqual(plist['ProgramArguments'][0], '/usr/bin/python3')
        self.assertEqual(plist['FunkInstallerOwner'], plist['Label'] + '.v1')
        self.assertEqual(watch.C.sizeof(watch.BSDInfo), 136)


if __name__ == '__main__':
    unittest.main()
