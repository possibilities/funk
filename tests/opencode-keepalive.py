#!/usr/bin/env python3
"""Public command/API effects through a fake CLI, without live session mutations.

This boundary owns route, location identity, ownership, readonly and retry
contracts. Regressions include grouping worktrees by repository, mutating a
foreign session, treating failed GETs as absence, creating fresh retry IDs or
dropping --server. Existing tests cover none of this command; no production
injection hooks or source-grep assertions are needed.
"""
import copy
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
COMMAND = [str(ROOT / 'bin/funk'), 'opencode-keepalive']
TITLE = 'Funk OpenCode keepalive (no prompts)'
OWNER = 'io.arthack.funk.opencode-keepalive.v1'


class Checks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='funk-opencode-test-')
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.home = self.directory / 'home'
        self.home.mkdir()
        self.bin = self.directory / 'bin'
        self.bin.mkdir()
        (self.bin / 'opencode').symlink_to(ROOT / 'tests/fixtures/opencode-keepalive')
        self.path = self.directory / 'api.json'
        self.write({'locations': [{'directory': '/projects/funk'}]})
        self.env = dict(os.environ, HOME=str(self.home), PATH=f'{self.bin}:/usr/bin:/bin',
                        FUNK_TEST_OPENCODE_STATE=str(self.path))

    def read(self):
        return json.loads(self.path.read_text())

    def write(self, state):
        self.path.write_text(json.dumps(state))

    def command(self, *args):
        return subprocess.run(COMMAND + list(args), env=self.env, capture_output=True,
                              text=True, timeout=10)

    def good(self, *args):
        result = self.command(*args)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def mutations(self, state=None):
        return [r for r in (state or self.read()).get('requests', []) if r['method'] != 'GET']

    def wait_for(self, process, condition):
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            if condition(self.read()):
                return
            if process.poll() is not None:
                self.fail('watcher exited before the expected API effect: ' + str(process.communicate()))
            time.sleep(0.02)
        self.fail('timed out waiting for isolated watcher API effects')

    def watcher(self, *args):
        process = subprocess.Popen(COMMAND + list(args), env=self.env, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True, start_new_session=True)
        def cleanup():
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
            process.communicate(timeout=5)
        self.addCleanup(cleanup)
        return process

    def stop(self, process):
        os.killpg(process.pid, signal.SIGINT)
        output, errors = process.communicate(timeout=5)
        self.assertEqual(process.returncode, 130, output + errors)
        self.assertNotIn('Traceback', output + errors)
        self.assertIn('no further heartbeats', output)
        return output, errors

    def test_exact_locations_worktrees_duplicates_reuse_and_explicit_server(self):
        directories = ['/projects/funk', '/worktrees/funk/change/funk', '/projects/other']
        foreign = {'id': 'ses_real_work', 'title': 'Real work', 'location': {'directory': directories[0]}}
        self.write({'locations': [{'directory': d} for d in directories + directories[:1]],
                    'sessions': {'ses_real_work': foreign}})
        server = 'http://127.0.0.1:12345'
        self.good('--once', '--server', server)
        self.good('--once', '--server', server)
        state = self.read()
        self.assertEqual(len(state['created']), 3)
        self.assertEqual(len(set(state['created'])), 3)
        self.assertTrue(all(i.startswith('ses_funk_keepalive_v1_') for i in state['created']))
        created = [r['payload'] for r in state['requests'] if r['method'] == 'POST']
        self.assertEqual([r['location'] for r in created], [{'directory': d} for d in directories])
        self.assertTrue(all(r['title'] == TITLE and r['metadata'] == {'funk.opencode-keepalive': OWNER}
                            for r in created))
        patches = [r for r in state['requests'] if r['method'] == 'PATCH']
        self.assertEqual(len(patches), 6)
        self.assertEqual({r['path'].rsplit('/', 1)[1] for r in patches}, set(state['created']))
        self.assertTrue(all(r['payload'] == {'title': TITLE} for r in patches))
        self.assertEqual(state['sessions']['ses_real_work'], foreign)
        self.assertTrue(all(r['server'] == server for r in state['requests']))
        self.assertEqual(state['scan_count'], 2)

    def test_dry_run_missing_and_existing_are_readonly_and_single_sweeps(self):
        result = self.good('--dry-run', '--interval', '0.01')
        self.assertIn('no local state writes, heartbeat or idle-eviction protection', result.stdout)
        self.assertIn('Would create/reuse and PATCH', result.stdout)
        self.assertEqual(self.mutations(), [])
        self.assertFalse((self.home / '.local').exists())
        self.assertEqual(self.read()['scan_count'], 1)
        self.good('--once')
        before = self.read()
        lock = self.home / '.local/state/funk/opencode-keepalive/runner.lock'
        lock_before = (lock.stat().st_mtime_ns, lock.read_bytes())
        result = self.good('--dry-run', '--once')
        after = self.read()
        self.assertIn('Would PATCH', result.stdout)
        self.assertEqual(after['sessions'], before['sessions'])
        self.assertEqual(self.mutations(after), self.mutations(before))
        self.assertEqual(after['scan_count'], before['scan_count'] + 1)
        self.assertEqual((lock.stat().st_mtime_ns, lock.read_bytes()), lock_before)
        self.assertEqual(lock.stat().st_mode & 0o777, 0o600)

    def test_strict_ownership_refuses_id_location_marker_and_title_changes(self):
        self.good('--once')
        state = self.read()
        identifier = state['created'][0]
        original = copy.deepcopy(state['sessions'][identifier])
        changes = [
            {'id': 'ses_foreign'}, {'location': {'directory': '/elsewhere'}},
            {'location': {'directory': '/projects/funk', 'workspaceID': 'remote'}},
            {'metadata': {}}, {'metadata': {'funk.opencode-keepalive': 'foreign'}},
            {'title': 'Repurposed working session'}, {'title': ''},
        ]
        for change in changes:
            with self.subTest(change=change):
                info = dict(copy.deepcopy(original), **change)
                state['sessions'][identifier] = info
                state['requests'] = []
                self.write(state)
                result = self.command('--once')
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn('refusing session', result.stderr)
                self.assertEqual(self.mutations(), [])
                self.assertEqual(self.read()['sessions'][identifier], info)

    def test_create_collision_is_validated_before_any_patch(self):
        self.write({'locations': [{'directory': '/projects/funk'}],
                    'create_collision': {'title': 'Foreign session', 'metadata': {}}})
        result = self.command('--once')
        self.assertEqual(result.returncode, 1)
        self.assertIn('refusing session', result.stderr)
        self.assertEqual([r['method'] for r in self.mutations()], ['POST'])
        self.assertEqual(next(iter(self.read()['sessions'].values()))['title'], 'Foreign session')

    def test_lost_create_response_reuses_the_same_id_on_later_invocation(self):
        for failure in [
            {'code': 1, 'stderr': 'HTTP 502 Bad Gateway\nAuthorization: SECRET_VALUE',
             'body': {'message': 'SECRET_VALUE'}},
            {'code': 0, 'raw': 'broken JSON SECRET_VALUE'},
        ]:
            with self.subTest(failure=failure):
                self.write({'locations': [{'directory': '/projects/funk'}],
                            'faults': [dict(failure, method='POST', path='/api/session', after=True)]})
                result = self.command('--once')
                self.assertEqual(result.returncode, 1)
                self.assertNotIn('SECRET_VALUE', result.stdout + result.stderr)
                self.assertNotIn('sweep complete', result.stdout)
                self.assertEqual(len(self.read()['created']), 1)
                self.assertEqual([r['method'] for r in self.mutations()], ['POST'])
                self.good('--once')
                state = self.read()
                self.assertEqual(len(state['created']), 1)
                self.assertEqual([r['method'] for r in self.mutations()], ['POST', 'PATCH'])

    def test_watcher_retries_rescans_new_locations_and_stops_cleanly(self):
        self.write({'scans': [[{'directory': '/projects/funk'}],
                              [{'directory': '/projects/funk'}, {'directory': '/worktrees/funk/new/funk'}]],
                    'faults': [{'method': 'GET', 'path': '/api/debug/location',
                                'code': 1, 'stderr': 'HTTP 503 Unavailable SECRET_VALUE'},
                               {'method': 'POST', 'path': '/api/session', 'after': True,
                                'code': 1, 'stderr': 'HTTP 502 Lost creation response'}]})
        process = self.watcher('--interval', '0.05', '--server', 'http://localhost:12345')
        self.wait_for(process, lambda s: any(
            r['method'] == 'PATCH' and s.get('sessions', {}).get(r['path'].rsplit('/', 1)[1], {})
            .get('location') == {'directory': '/worktrees/funk/new/funk'}
            for r in s.get('requests', [])))
        output, errors = self.stop(process)
        self.assertIn('Transient failure; will rescan/retry', errors)
        self.assertIn('Protection is not assured', errors)
        self.assertNotIn('SECRET_VALUE', output + errors)
        state = self.read()
        self.assertGreaterEqual(state['scan_count'], 2)
        self.assertEqual(len(state['created']), 2)
        self.assertTrue(all(r['server'] == 'http://localhost:12345' for r in state['requests']))
        time.sleep(0.1)
        self.assertEqual(self.read(), state)

    def test_failed_or_nonempty_patch_reply_is_not_a_confirmed_heartbeat(self):
        for failure in [
            {'code': 1, 'stderr': 'HTTP 503 Unavailable SECRET_VALUE'},
            {'code': 0, 'body': {'unexpected': 'SECRET_VALUE'}},
        ]:
            with self.subTest(failure=failure):
                self.write({'locations': [{'directory': '/projects/funk'}],
                            'faults': [dict(failure, method='PATCH')]})
                result = self.command('--once')
                self.assertEqual(result.returncode, 1)
                self.assertNotIn('SECRET_VALUE', result.stdout + result.stderr)
                self.assertNotIn('Heartbeat confirmed', result.stdout)
                self.assertNotIn('sweep complete', result.stdout)
                self.good('--once')
                self.assertEqual(len(self.read()['created']), 1)

    def test_local_lock_rejects_second_runner_and_releases_on_ctrl_c(self):
        process = self.watcher()
        self.wait_for(process, lambda s: any(r['method'] == 'PATCH' for r in s.get('requests', [])))
        before = self.read()
        result = self.command('--once', '--server', 'http://localhost:12345')
        self.assertEqual(result.returncode, 1)
        self.assertIn('another keepalive runner', result.stderr)
        self.assertEqual(self.read(), before)
        output, _ = self.stop(process)
        self.assertIn('interval 1200s', output)
        self.good('--once')
        self.assertEqual(len(self.read()['created']), 1)

    def test_malformed_or_incompatible_loaded_locations_fail_before_mutation(self):
        responses = [
            {'body': {'data': [{'directory': '/projects/funk'}]}},
            {'raw': '{invalid'}, {'raw': ''},
            {'body': [{'directory': 'relative'}]}, {'body': [{'directory': 7}]},
            {'body': [{'directory': '/projects/funk'}, {'directory': '/x', 'workspaceID': 'remote'}]},
            {'body': [{'directory': '/x', 'remote': 'server'}]}, {'body': [None]},
        ]
        for response in responses:
            with self.subTest(response=response):
                self.write({'faults': [dict(response, method='GET', path='/api/debug/location', code=0)]})
                result = self.command('--once')
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertEqual(self.mutations(), [])
                self.assertEqual(len(self.read()['requests']), 1)

    def test_only_a_typed_matching_404_allows_creation(self):
        for response in [
            {'body': {'_tag': 'SessionNotFoundError', 'sessionID': 'ses_wrong'}, 'stderr': 'HTTP 404 Not Found'},
            {'body': {'_tag': 'UnauthorizedError'}, 'stderr': 'HTTP 401 Unauthorized'},
            {'raw': 'not JSON', 'stderr': 'HTTP 404 Not Found'},
            {'body': {'message': 'SECRET_VALUE'}, 'stderr': 'SECRET_VALUE connection lost'},
        ]:
            with self.subTest(response=response):
                self.write({'locations': [{'directory': '/projects/funk'}]})
                # The fault must reach the session GET, not the loaded-location GET.
                self.good('--dry-run')
                identifier = self.read()['requests'][-1]['path'].rsplit('/', 1)[1]
                self.write({'locations': [{'directory': '/projects/funk'}],
                            'faults': [dict(response, method='GET', path='/api/session/' + identifier, code=1)]})
                result = self.command('--once')
                self.assertEqual(result.returncode, 1)
                self.assertNotIn('SECRET_VALUE', result.stdout + result.stderr)
                self.assertEqual(self.mutations(), [])

    def test_empty_server_and_cli_validation_do_not_claim_protection(self):
        self.write({'locations': []})
        result = self.good('--once')
        self.assertIn('no locations heartbeated', result.stdout)
        self.assertIn('check --server URL', result.stdout)
        self.assertEqual(self.mutations(), [])
        self.assertIn('opencode-keepalive', subprocess.run([str(ROOT / 'bin/funk'), 'help'],
                      env=self.env, capture_output=True, text=True, timeout=5).stdout)
        self.assertIn('--dry-run', self.good('--help').stdout)
        for value in ('0', '-1', '1800.1', 'nan', 'inf'):
            with self.subTest(interval=value):
                result = self.command('--interval', value, '--once')
                self.assertEqual(result.returncode, 2)
        result = self.command('--server', 'http://user:SECRET_VALUE@localhost:12345', '--once')
        self.assertEqual(result.returncode, 2)
        self.assertNotIn('SECRET_VALUE', result.stdout + result.stderr)
        self.assertEqual(len(self.read()['requests']), 1)


if __name__ == '__main__':
    unittest.main()
