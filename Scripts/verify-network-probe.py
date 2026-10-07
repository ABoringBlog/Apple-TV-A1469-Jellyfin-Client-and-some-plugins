#!/usr/bin/env python3
"""Verify a dedicated Probe9 capture, without printing header values or URLs."""
import argparse
import json
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('requests', type=Path)
p.add_argument('device_log', type=Path)
p.add_argument('--peer', required=True)
a = p.parse_args()
rows = [json.loads(line) for line in a.requests.read_text().splitlines() if line]
rows = [row for row in rows if row.get('peer') == a.peer]
log = a.device_log.read_text()
marker = 'NETWORK_BEGIN probe=9 synthetic=1 fullscreen=0 gateway=1'
run = log.rsplit(marker, 1)[-1] if marker in log else ''
checks = {}
checks['completed_device_run'] = bool(run) and 'NETWORK_END' in run and 'NETWORK_EXCEPTION' not in run
checks['all_cases_prepared_cued_stopped'] = all(
    f'NETWORK_{stage} case={i} ' in run and any(
        line.startswith(f'NETWORK_{stage} case={i} ') and f'{field}=1' in line
        for line in run.splitlines())
    for i in range(7) for stage, field in [('PREPARE', 'prepared'), ('CUE', 'cued'), ('STOP', 'stopped')])
checks['device_requests_present'] = bool(rows)
checks['no_secondary_requests'] = bool(rows) and all(r.get('origin') == 'primary' for r in rows)
checks['all_upstream_requests_authenticated'] = bool(rows) and all(
    r.get('authorizationPresent') is True and r.get('syntheticMatch') is True for r in rows)
paths = {r.get('path') for r in rows if r.get('httpStatus') == 200}
required = {'/plain/clip.mp4'}
for prefix in ('plain', 'encrypted'):
    required.update(f'/{prefix}/{leaf}' for leaf in ('master.m3u8', 'media.m3u8'))
    required.update(f'/{prefix}/segment{i:02d}.ts' for i in range(6))
required.add('/encrypted/key.bin')
checks['mp4_hls_segments_key_requested'] = required <= paths
checks['external_child_playlist_exercised'] = {'/child/master.m3u8', '/child/media.m3u8'} <= paths
redirects = {r.get('path') for r in rows if r.get('httpStatus') == 302}
checks['redirect_cases_exercised'] = {'/same/master.m3u8', '/cross/master.m3u8'} <= redirects and any(
    path.startswith('/segment-redirect/redirect-segment') for path in redirects)
print(json.dumps({'passed': all(checks.values()), 'device_request_count': len(rows), 'checks': checks}, indent=2))
raise SystemExit(0 if all(checks.values()) else 1)
