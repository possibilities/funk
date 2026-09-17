#!/usr/bin/env python3
"""Synthetic Artbird browser-pressure checks; never use SSH or AgentNotify."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'libexec' / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


watch = load('artbird_watch', 'artbird-browser-watchdog.py')
installer = load('artbird_installer', 'install-artbird-browser-watchdog-agent.py')


def snapshot(temperature=44, cpu=0, browsers=None, errors=None):
    hypervisors = [] if not cpu else [{
        'pid': 42, 'ppid': 1, 'elapsed_seconds': 3600,
        'cpu_percent': cpu, 'memory_percent': 1.5, 'command': 'cloud-hypervisor',
    }]
    return {
        'sampled_at': 10000, 'host': 'artbird',
        'remote': {'max_temperature_celsius': temperature, 'load_average': [0.1, 0.2, 0.3],
                   'browser_hypervisors': hypervisors, 'top_processes': hypervisors,
                   'temperatures': []},
        'browsers': browsers or ([] if not hypervisors else [{'name': 'target', 'state': 'running'}]),
        'sessions': [], 'errors': errors or [],
    }


class Checks(unittest.TestCase):
    def test_thresholds_require_sustained_warning_but_critical_is_immediate(self):
        with tempfile.TemporaryDirectory() as raw:
            state, sent = Path(raw), []
            send = lambda path, params: sent.append(dict(params))
            watch.check(state, snapshot(cpu=90), send, now=10000)
            self.assertEqual(sent, [])
            result = watch.check(state, snapshot(cpu=90), send, now=10300)
            self.assertEqual(result['effective_level'], 1)
            self.assertEqual(len(sent), 1)
            watch.check(state, snapshot(temperature=92, cpu=90), send, now=10600)
            self.assertEqual(len(sent), 2)
            self.assertIn('critical', sent[-1]['title'].lower())
            self.assertEqual(len({item['group'] for item in sent}), 1)

    def test_two_healthy_samples_send_one_recovery(self):
        with tempfile.TemporaryDirectory() as raw:
            state, sent = Path(raw), []
            send = lambda path, params: sent.append(dict(params))
            watch.check(state, snapshot(temperature=92), send, now=10000)
            watch.check(state, snapshot(), send, now=10300)
            self.assertEqual(len(sent), 1)
            watch.check(state, snapshot(), send, now=10600)
            self.assertEqual(len(sent), 2)
            self.assertIn('recovered', sent[-1]['title'].lower())

    def test_failed_delivery_reuses_exact_request(self):
        with tempfile.TemporaryDirectory() as raw:
            state, attempts = Path(raw), []

            def fail(path, params):
                attempts.append(dict(params))
                raise OSError('notifier unavailable')

            with self.assertRaises(OSError):
                watch.check(state, snapshot(temperature=92), fail, now=10000)
            watch.check(state, snapshot(temperature=92),
                        lambda path, params: attempts.append(dict(params)), now=10300)
            self.assertEqual(attempts[0], attempts[1])
            self.assertNotIn('pending', json.loads((state / 'state.json').read_text()))

    def test_unknown_targets_and_observation_failure_are_bounded(self):
        unknown = snapshot(browsers=[{'name': 'stale', 'state': 'unknown'}])
        finding = watch.evaluate(unknown)
        self.assertEqual(finding['level'], 1)
        self.assertEqual(finding['required_streak'], 3)
        failed = snapshot(errors=[{'source': 'ssh', 'message': 'offline'}])
        failed['remote'] = None
        finding = watch.evaluate(failed)
        self.assertIn('observation_failed', finding['signature'])

    def test_installer_renders_a_short_lived_owned_job(self):
        plist = installer.render(Path('/checkout'), Path('/home/test'))
        self.assertEqual(plist['StartInterval'], 300)
        self.assertTrue(plist['RunAtLoad'])
        self.assertNotIn('KeepAlive', plist)
        self.assertEqual(plist['ProgramArguments'][0], '/usr/bin/python3')
        self.assertIn('--host', plist['ProgramArguments'])
        self.assertEqual(plist['EnvironmentVariables']['HOME'], '/home/test')
        self.assertIn('/opt/homebrew/bin', plist['EnvironmentVariables']['PATH'])
        self.assertEqual(plist['FunkInstallerOwner'], plist['Label'] + '.v1')
        self.assertIn('"$funk_command" install-artbird-watchdog',
                      (ROOT / 'install').read_text())
        self.assertIn('install-artbird-watchdog)', (ROOT / 'bin/funk').read_text())


if __name__ == '__main__':
    unittest.main()
