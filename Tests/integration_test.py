#!/usr/bin/env python3
"""Contract tests: validation happens before I/O and output cannot echo secrets."""
import contextlib
import io
import json
import os
import tempfile
import subprocess
import unittest
from unittest.mock import patch
import integration

class EntryTests(unittest.TestCase):
    def invoke(self, config):
        return subprocess.run(['build/integration'], input=json.dumps(config).encode(), capture_output=True, timeout=5)

    def test_invalid_types_and_modes(self):
        base = dict(url='http://fixture.invalid/jellyfin', fixture=True,
                    username='测试用户', password='p"ass', mode='server')
        for key in ('url', 'mode', 'username', 'password', 'library', 'item', 'fixture', 'allow_http'):
            for value in (None, [], {}, 3):
                with self.subTest(key=key, value=value):
                    self.assertEqual(self.invoke(dict(base, **{key: value})).returncode, 2)
        for config in ([], None, {}, dict(base, mode='unknown'), dict(base, url='file:///secret'),
                       dict(base, library='../secret'), dict(base, fixture=False),
                       dict(base, fixture=False, mode='tls-invalid')):
            self.assertIn(self.invoke(config).returncode, (2, 77))

    def test_fixture_pages(self):
        result = subprocess.run(['python3', 'Tests/integration.py', '--fixture'], capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn(b'PASS: first media page', result.stdout)
        self.assertIn(b'PASS: second media page', result.stdout)
        self.assertNotIn(b'SKIP:', result.stdout)

    def test_user_token_authentication_and_revocation(self):
        result=self.invoke(dict(url='http://fixture.invalid/jellyfin',fixture=True,token='fixture-token',mode='server',library='lib1',item='movie1'))
        self.assertEqual(result.returncode,0,result.stdout)
        self.assertIn(b'PASS: server logout and token invalidation',result.stdout)
        self.assertNotIn(b'fixture-token',result.stdout+result.stderr)

    def test_cli_exit_codes(self):
        for args, code in (([], 77), (['--url', 'http://localhost'], 77),
                           (['--url', 'https://user:secret@localhost'], 2),
                           (['--mode', 'secret'], 2), (['--fixture', '--mode', 'probe'], 2)):
            result = subprocess.run(['python3', 'Tests/integration.py'] + args, capture_output=True, timeout=5)
            self.assertEqual(result.returncode, code)
            self.assertNotIn(b'secret', result.stdout + result.stderr)

    def test_external_config_and_environment(self):
        base = {'url': 'https://server.invalid/jellyfin', 'username': 'SECRET_USER',
                'password': 'SECRET_PASSWORD', 'library': 'lib1', 'item': 'movie1'}
        with tempfile.NamedTemporaryFile(mode='w') as f:
            json.dump(base, f); f.flush()
            with patch('sys.argv', ['integration.py', '--config', f.name]), patch.dict(os.environ, {}, clear=True), patch('subprocess.run') as run:
                run.return_value = subprocess.CompletedProcess([], 0, b'Authorization: SECRET\n', b'SECRET')
                with contextlib.redirect_stdout(io.StringIO()) as out:
                    self.assertEqual(integration.main(), 0)
                self.assertNotIn('SECRET', out.getvalue())
                sent = json.loads(run.call_args.kwargs['input'])
                self.assertEqual(sent['password'], base['password'])
                self.assertNotIn('SECRET', str(run.call_args.args))
        with patch('sys.argv', ['integration.py']), patch.dict(os.environ, {'JF_URL': base['url'], 'JF_TOKEN': 'SECRET_TOKEN'}, clear=True), patch('subprocess.run') as run:
            run.return_value = subprocess.CompletedProcess([], 0, b'', b'')
            self.assertEqual(integration.main(), 0)
            self.assertEqual(json.loads(run.call_args.kwargs['input'])['token'], 'SECRET_TOKEN')

    def test_redaction_and_runner_failures(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            integration.safe_output(b'PASS: secret\nFAIL: authentication (error-code=401) secret\nPASS: authentication (error-code=0)\n')
        self.assertEqual(output.getvalue(), 'PASS: authentication (error-code=0)\n')
        for failure in (OSError('secret'), subprocess.TimeoutExpired('secret', 90)):
            with patch('sys.argv', ['integration.py', '--fixture']), patch('subprocess.run', side_effect=failure), contextlib.redirect_stdout(io.StringIO()) as captured:
                self.assertEqual(integration.main(), 1)
                self.assertNotIn('secret', captured.getvalue())

if __name__ == '__main__':
    unittest.main()
