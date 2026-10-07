#!/usr/bin/env python3
"""Real loopback TLS: isolated CA trust, hostname rejection, untrusted CA, handshake.
No system trust edits; this validates TLS fixtures, not Foundation/ATV TLS success.
Foundation self-signed rejection is separately exercised by Tests/run.py.
"""
import http.server
import ssl
import subprocess
import tempfile
import threading
import unittest
from pathlib import Path
from urllib.request import urlopen
from urllib.error import URLError

class Quiet(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b'{}')

class TLSContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='jf-tls-')
        cls.root = Path(cls.temp.name)
        def openssl(*args):
            subprocess.run(['openssl', *args], cwd=cls.root, check=True, capture_output=True)
        (cls.root/'ca.cnf').write_text('[req]\ndistinguished_name=dn\nx509_extensions=v3\n[dn]\n[v3]\nbasicConstraints=critical,CA:true\nkeyUsage=critical,keyCertSign,cRLSign\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid:always\n')
        openssl('req', '-config', 'ca.cnf', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1', '-subj', '/CN=Fixture CA', '-keyout', 'ca.key', '-out', 'ca.pem')
        openssl('req', '-newkey', 'rsa:2048', '-nodes', '-subj', '/CN=localhost', '-keyout', 'server.key', '-out', 'server.csr')
        (cls.root/'ext').write_text('subjectAltName=DNS:localhost\nextendedKeyUsage=serverAuth\nkeyUsage=critical,digitalSignature,keyEncipherment\nbasicConstraints=critical,CA:false\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid,issuer\n')
        openssl('x509', '-req', '-in', 'server.csr', '-CA', 'ca.pem', '-CAkey', 'ca.key', '-CAcreateserial', '-days', '1', '-extfile', 'ext', '-out', 'server.pem')
        cls.server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Quiet)
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(cls.root/'server.pem', cls.root/'server.key')
        cls.server.socket = ctx.wrap_socket(cls.server.socket, server_side=True)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True); cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown(); cls.server.server_close(); cls.thread.join(); cls.temp.cleanup()

    def test_trusted_https_success(self):
        ctx = ssl.create_default_context(cafile=str(self.root/'ca.pem'))
        with urlopen(f'https://localhost:{self.server.server_port}', context=ctx, timeout=3) as r:
            self.assertEqual(r.read(), b'{}')

    def test_hostname_mismatch(self):
        ctx = ssl.create_default_context(cafile=str(self.root/'ca.pem'))
        with self.assertRaises(URLError) as caught:
            urlopen(f'https://127.0.0.1:{self.server.server_port}', context=ctx, timeout=3)
        self.assertIsInstance(caught.exception.reason, ssl.SSLCertVerificationError)
        self.assertEqual(caught.exception.reason.verify_code, 64)

    def test_untrusted_ca(self):
        with self.assertRaises(URLError) as caught:
            urlopen(f'https://localhost:{self.server.server_port}', context=ssl.create_default_context(), timeout=3)
        self.assertIsInstance(caught.exception.reason, ssl.SSLCertVerificationError)
        self.assertNotEqual(caught.exception.reason.verify_code, 64)

    def test_tls_handshake_failure(self):
        plain = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Quiet)
        thread = threading.Thread(target=plain.serve_forever, daemon=True); thread.start()
        try:
            with self.assertRaises(URLError) as caught:
                urlopen(f'https://127.0.0.1:{plain.server_port}', timeout=3)
            self.assertIsInstance(caught.exception.reason, ssl.SSLError)
            self.assertNotIsInstance(caught.exception.reason, ssl.SSLCertVerificationError)
        finally:
            plain.shutdown(); plain.server_close(); thread.join()

if __name__ == '__main__': unittest.main()
