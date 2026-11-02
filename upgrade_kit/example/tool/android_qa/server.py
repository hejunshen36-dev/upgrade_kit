"""Loopback-only version/APK server for manual Android example QA.

Use adb -s <authorized-device> reverse tcp:8765 tcp:8765. This server is test-only;
the deliberate bad digest and HTTP toggle must not be used in production.
"""
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import threading
import time
from urllib.parse import parse_qs, urlparse

parser = argparse.ArgumentParser()
parser.add_argument('--apk', type=Path, required=True)
parser.add_argument('--port', type=int, default=8765)
parser.add_argument('--log', type=Path, required=True)
args = parser.parse_args()
payload = args.apk.read_bytes()
digest = hashlib.sha256(payload).hexdigest()
state = {'delay': 0.1, 'fail_next': False}
lock = threading.Lock()

def record(**values):
    values['time'] = time.time()
    with lock, args.log.open('a') as output:
        output.write(json.dumps(values) + '\n')

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == '/control':
            query = parse_qs(url.query)
            if 'delay' in query:
                state['delay'] = max(0, min(1, float(query['delay'][0])))
            if 'fail_next' in query:
                state['fail_next'] = query['fail_next'][0] == '1'
            body = json.dumps(state).encode()
            self.send_response(200); self.end_headers(); self.wfile.write(body)
            return
        if url.path.startswith('/release/'):
            scenario = url.path.rsplit('/', 1)[-1]
            body = json.dumps({
                'versionCode': '1' if scenario == 'no-update' else '2',
                'versionName': '1.1.0',
                'downloadUrl': f'http://127.0.0.1:{args.port}/app.apk',
                'sha256': '0' * 64 if scenario == 'bad' else digest,
                'releaseNotes': f'Android example QA: {scenario}. Host confirmation is required.',
            }).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers(); self.wfile.write(body)
            record(event='manifest', scenario=scenario)
            return
        if url.path != '/app.apk':
            self.send_error(404); return
        if state['fail_next']:
            state['fail_next'] = False
            self.send_error(503, 'Deliberate QA failure')
            record(event='apk-failed', status=503)
            return
        sent = 0
        self.send_response(200)
        self.send_header('Content-Type', 'application/vnd.android.package-archive')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        try:
            for offset in range(0, len(payload), 1024):
                chunk = payload[offset:offset + 1024]
                self.wfile.write(chunk); self.wfile.flush()
                sent += len(chunk)
                time.sleep(state['delay'])
            record(event='apk-complete', bytes=sent)
        except (BrokenPipeError, ConnectionResetError):
            record(event='apk-disconnected', bytes=sent)

record(event='server-start', apk=str(args.apk), size=len(payload), sha256=digest)
ThreadingHTTPServer(('127.0.0.1', args.port), Handler).serve_forever()
