#!/usr/bin/env python3
"""Isolated synthetic ATV probe endpoint. Logs names/presence only, never values."""
import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import threading
import time
from urllib.parse import urlsplit

p = argparse.ArgumentParser()
p.add_argument('--bind', default='127.0.0.1')
p.add_argument('--port', type=int, default=18780)
p.add_argument('--fixture', type=Path, required=True)
p.add_argument('--log', type=Path, required=True)
p.add_argument('--encrypted-fixture', type=Path)
a = p.parse_args()
log = a.log.open('x', buffering=1)
lock = threading.Lock()
synthetic = 'Bearer JF-PROBE-ONLY-12H1006'

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        path = urlsplit(self.path).path
        secondary = self.server.server_port != a.port
        fixture = a.encrypted_fixture if path.startswith('/encrypted/') and a.encrypted_fixture else a.fixture
        status = 200
        content_type = 'application/vnd.apple.mpegurl'
        location = None
        if path.endswith('/clip.mp4'):
            body = (a.fixture/'clip.mp4').read_bytes()
            content_type = 'video/mp4'
        elif path.endswith('/key.bin'):
            body = (fixture/'key.bin').read_bytes()
            content_type = 'application/octet-stream'
        elif path == '/same/master.m3u8':
            location = '/plain/master.m3u8'
        elif path == '/cross/master.m3u8':
            location = f'http://{a.bind}:{a.port+1}/plain/master.m3u8'
        elif path.endswith('/master.m3u8'):
            body = b'#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=400000,CODECS="avc1.42c00c,mp4a.40.2",RESOLUTION=320x180\nmedia.m3u8\n'
        elif path.endswith('/media.m3u8'):
            body = (fixture/'media.m3u8').read_bytes()
            if path.startswith('/child/'):
                body = body.replace(b'segment', f'http://{a.bind}:{a.port+1}/plain/segment'.encode())
            if path.startswith('/segment-redirect/'):
                body = body.replace(b'segment', b'redirect-segment')
        elif '/redirect-segment' in path:
            location = f'http://{a.bind}:{a.port+1}/plain/'+path.rsplit('/',1)[1].replace('redirect-','')
        elif path.rsplit('/',1)[-1] in {f'segment{i:02d}.ts' for i in range(6)}:
            body = (fixture/path.rsplit('/',1)[-1]).read_bytes()
            content_type = 'video/mp2t'
        else:
            status,body,content_type = 404,b'', 'text/plain'
        with lock:
            log.write(json.dumps({'time':time.time(), 'peer':self.client_address[0],
                'path':path, 'origin':'secondary' if secondary else 'primary',
                'sameOrigin':not secondary, 'httpStatus':302 if location else status,
                'headerNames':sorted(self.headers.keys()),
                'authorizationPresent':'Authorization' in self.headers,
                'syntheticMatch':self.headers.get('Authorization') == synthetic})+'\n')
        if location:
            self.send_response(302); self.send_header('Location',location)
            self.send_header('Content-Length','0'); self.end_headers(); return
        self.send_response(status)
        self.send_header('Content-Type',content_type)
        self.send_header('Content-Length',str(len(body)))
        self.end_headers()
        try: self.wfile.write(body)
        except (BrokenPipeError,ConnectionResetError): pass

servers = [ThreadingHTTPServer((a.bind,port),Handler) for port in [a.port,a.port+1]]
for server in servers:
    threading.Thread(target=server.serve_forever,daemon=True).start()
print('Synthetic probe server ready; values are never logged.',flush=True)
try:
    while True: time.sleep(1)
except KeyboardInterrupt:
    for server in servers: server.shutdown()
    log.close()
