#!/usr/bin/env python3
"""Loopback fixture only; never contacts a Jellyfin server or Apple TV."""
import argparse
import ssl
import tempfile
import http.server
import json
import subprocess
import threading
import errno
import sys
import time
from integration import safe_output
from pathlib import Path

MEDIA = json.loads((Path(__file__).parent / "media.json").read_text())

def auth_token(headers):
    auth = headers.get('Authorization', '')
    marker = 'Token="'
    if marker not in auth:
        return None
    tail = auth.split(marker, 1)[1]
    return tail.split('"', 1)[0] if '"' in tail else None

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, status, body):
        data = json.dumps(body, ensure_ascii=False).encode() if not isinstance(body, bytes) else body
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass  # Client timeout/cancellation deliberately closes the socket.

    logged_out = False
    retries = 0
    def do_GET(self):
        if self.path == '/jellyfin/Users/Me':
            return self.reply(401 if Handler.logged_out else 200, {'Id': 'user1'})
        if '/Subtitles/' in self.path:
            return self.reply(200, b'bad' if '/99/' in self.path else b'1\n00:00:01,000 --> 00:00:02,000\nSubtitle\n')
        if '/Images/' in self.path:
            if auth_token(self.headers) != 'fixture-token' or '/expired/' in self.path:
                return self.reply(401, {})
            if '/oversized/' in self.path:
                return self.reply(200, b'x' * (8 * 1024 * 1024 + 1))
            if '/retry/' in self.path:
                Handler.retries += 1
                if Handler.retries == 1:
                    return self.reply(503, {})
            return self.reply(200, b'bad image' if '/broken/' in self.path else (Path(__file__).parent / 'pixel.png').read_bytes())
        if self.path in MEDIA:
            route = MEDIA[self.path]
            if auth_token(self.headers) != 'fixture-token':
                return self.reply(401, {})
            return self.reply(route['status'], route['body'])
        if self.path.startswith('/oversize/'):
            return self.reply(200, b' ' * (8 * 1024 * 1024 + 1))
        if self.path.startswith('/slow'):
            time.sleep(1)
            return self.reply(200, {})
        if self.path.startswith('/disconnect/'):
            self.connection.close()
            return
        if self.path.startswith('/redirect/'):
            self.send_response(302)
            self.send_header('Location', '/forbidden')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        if self.path.startswith('/invalid/'):
            return self.reply(200, b'{broken')
        if self.path.startswith('/array/'):
            return self.reply(200, [])
        if self.path.startswith('/http500/'):
            return self.reply(500, {})
        if self.path == '/jellyfin/System/Info/Public':
            return self.reply(200, {'ServerName': '测试服务器'})
        if self.path == '/jellyfin/Users/user1/Views':
            token = auth_token(self.headers)
            if token == 'empty':
                return self.reply(200, {'Items': []})
            if token == 'items':
                return self.reply(200, {'Items': [None]})
            if token == 'fixture-token':
                return self.reply(200, {'Items': [{'Id': 'lib1', 'Name': '电影'}]})
        self.reply(404, {})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        if self.path.endswith('/PlaybackInfo'):
            item = self.path.split('/')[-2]
            if auth_token(self.headers) != 'fixture-token' or item == 'expired': return self.reply(401, {})
            if item == 'slow': time.sleep(1)
            if item == 'disconnect': self.connection.close(); return
            if item == 'oversized': return self.reply(200, b'x' * (8 * 1024 * 1024 + 1))
            if item == 'empty': return self.reply(200, {'PlaySessionId': 'play1', 'MediaSources': []})
            if item == 'malformed': return self.reply(200, {'MediaSources': 'bad'})
            if body.get('StartTimeTicks') != 100 or body.get('DeviceProfile', {}).get('DirectPlayProfiles', [{}])[0].get('VideoCodec') != 'h264': return self.reply(400, {})
            return self.reply(200, json.loads((Path(__file__).parent/'playback.json').read_text()))
        if '/Sessions/Playing' in self.path:
            if auth_token(self.headers) != 'fixture-token' or body.get('PlaySessionId') != 'play1': return self.reply(400, {})
            return self.reply(204, b'')
        if self.path == '/jellyfin/Sessions/Logout':
            Handler.logged_out = True
            return self.reply(204, b'')
        Handler.logged_out = False
        auth = self.headers.get('Authorization', '')
        if self.path != '/jellyfin/Users/AuthenticateByName' or 'DeviceId="test-device"' not in auth or not auth.startswith('MediaBrowser ') or self.headers.get('Content-Type') != 'application/json':
            return self.reply(400, {})
        if body['Username'] == 'bad':
            return self.reply(401, {})
        if body['Username'] == 'shape':
            return self.reply(200, {'AccessToken': None, 'User': []})
        if body['Username'] in ('empty', 'items'):
            return self.reply(200, {'AccessToken': body['Username'], 'User': {'Id': 'user1'}})
        if body != {'Username': '测试用户', 'Pw': 'p"ass'}:
            return self.reply(400, {})
        self.reply(200, {'AccessToken': 'fixture-token', 'User': {'Id': 'user1'}})

parser = argparse.ArgumentParser()
parser.add_argument('--tls-cert')
parser.add_argument('--tls-key')
parser.add_argument('--self-signed', action='store_true')
parser.add_argument('--integration', action='store_true')
parser.add_argument('--playback', action='store_true')
args = parser.parse_args()
if args.integration and (args.self_signed or args.tls_cert):
    parser.error('--integration is a loopback HTTP entry test')
if bool(args.tls_cert) != bool(args.tls_key) or (args.self_signed and args.tls_cert):
    parser.error('use both --tls-cert and --tls-key, or --self-signed')
try:
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
except PermissionError as exc:
    if exc.errno in (errno.EPERM, errno.EACCES):
        print('BLOCKED: environment denied loopback bind before any client tests; run make test-http in a permitted terminal.', file=sys.stderr)
        raise SystemExit(77)
    raise
temporary = tempfile.TemporaryDirectory(dir='build', prefix='tls-fixture-')
if args.self_signed:
    args.tls_cert = str(Path(temporary.name) / 'cert.pem')
    args.tls_key = str(Path(temporary.name) / 'key.pem')
    subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                    '-keyout', args.tls_key, '-out', args.tls_cert, '-days', '1',
                    '-subj', '/CN=localhost'], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
if args.tls_cert:
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(args.tls_cert, args.tls_key)
    server.socket = context.wrap_socket(server.socket, server_side=True)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    scheme = 'https' if args.tls_cert else 'http'
    url = f'{scheme}://127.0.0.1:{server.server_port}'
    if args.playback:
        result = subprocess.run(['build/playback-http', url + '/jellyfin'], timeout=45)
    elif args.integration:
        cases = [
            ({'url': url + '/jellyfin', 'mode': 'server', 'username': '测试用户', 'password': 'p"ass', 'library': 'lib1', 'item': 'movie1'}, 0),
            ({'url': url + '/jellyfin', 'mode': 'server', 'username': 'bad', 'password': ''}, 1),
            ({'url': url + '/jellyfin', 'mode': 'probe'}, 0),
            ({'url': url + '/slow', 'mode': 'timeout'}, 0),
            ({'url': url + '/disconnect', 'mode': 'offline'}, 0),
            ({'url': url + '/http500', 'mode': 'probe'}, 1),
        ]
        failed = False
        for config, expected in cases:
            config['allow_http'] = True
            result = subprocess.run(['build/integration'], input=json.dumps(config).encode(), timeout=45,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            safe_output(result.stdout)
            if result.returncode != expected:
                failed = True
        result = subprocess.CompletedProcess([], int(failed))
        print(('FAIL' if failed else 'PASS') + ': HTTP integration exit-code contracts')
    elif args.self_signed:
        result = subprocess.run(['build/integration'], input=json.dumps({'url': url + '/jellyfin', 'mode': 'tls-invalid'}).encode(), timeout=45, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        safe_output(result.stdout)
    else:
        result = subprocess.run(['build/tests', url], timeout=45)
finally:
    server.shutdown()
    server.server_close()
    temporary.cleanup()
raise SystemExit(result.returncode)
