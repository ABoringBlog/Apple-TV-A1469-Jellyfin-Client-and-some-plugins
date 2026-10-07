#!/usr/bin/env python3
"""Explicit, staged SSH deployment. Dry-run by default; never discovers devices."""
import argparse
import hashlib
import importlib.util
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
PKG = 'org.jellyfin.atv3'
MUTATING = {'upload', 'backup', 'install', 'rollback', 'uninstall'}
ACTIONS = ('connect', 'preflight', 'disk', 'upload', 'backup', 'install', 'inspect', 'rollback', 'uninstall', 'diagnostics', 'crashes')

def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('action', choices=ACTIONS)
    p.add_argument('--host', required=True, help='explicit SSH alias or root@host, no password')
    p.add_argument('--port', type=int, default=22)
    p.add_argument('--run-id', default='pre-device', help='unique device-side backup directory suffix')
    p.add_argument('--package', type=Path)
    p.add_argument('--sha256')
    p.add_argument('--rollback-package', type=Path, help='original installed deb for an upgrade backup')
    p.add_argument('--output', type=Path, default=ROOT / 'logs/device')
    p.add_argument('--execute', action='store_true')
    p.add_argument('--device-confirmed', action='store_true', help='operator verified firmware, loader and SSH recovery access')
    p.add_argument('--include-sensitive-logs', action='store_true', help='store raw logs locally without printing them')
    return p

def validate(a):
    if not re.fullmatch(r'(?:root@)?[A-Za-z0-9][A-Za-z0-9._-]*', a.host):
        raise ValueError('Use a simple SSH alias/hostname or root@host')
    if not 1 <= a.port <= 65535 or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{0,63}', a.run_id):
        raise ValueError('Invalid port or run ID')
    if a.execute and a.action in MUTATING and not a.device_confirmed:
        raise ValueError('Mutations require --execute --device-confirmed after preflight review')
    if a.action in ('upload', 'install') and (not a.package or not a.sha256 or not re.fullmatch(r'[0-9a-f]{64}', a.sha256)):
        raise ValueError('Upload/install require --package and its --sha256')

def verify_package(path, expected=None):
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if expected and digest != expected:
        raise ValueError('Local package SHA256 mismatch')
    spec = importlib.util.spec_from_file_location('verify_package', ROOT / 'Scripts/verify-package.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    version = module.verify(path)
    return digest, version

def remote_dir(a): return '/var/root/jf-pd-' + a.run_id

def ssh_args(a):
    return ['ssh', '-p', str(a.port), '-o', 'ConnectTimeout=10', '-o', 'StrictHostKeyChecking=yes',
            '-o', 'ServerAliveInterval=10', '-o', 'ServerAliveCountMax=3', a.host]

HASH = '''hash_file() {
    if command -v shasum >/dev/null 2>&1; then
        set -- $(shasum -a 256 "$1"); printf '%s\\n' "$1";
    elif command -v sha256sum >/dev/null 2>&1; then
        set -- $(sha256sum "$1"); printf '%s\\n' "$1";
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$1" | sed 's/^.*= //';
    else exit 72; fi
}
'''
STATE = '''package_state() {
    dpkg-query -W -f='${Status} ${Version}' org.jellyfin.atv3 2>/dev/null || true
}
'''

def script(a, digest=None, version=None):
    d = shlex.quote(remote_dir(a))
    base = 'set -eu\n' + HASH + STATE
    gate = '''test "$(id -u)" = 0
test "$(dpkg --print-architecture)" = iphoneos-arm
test -d /Applications/AppleTV.app
test -w /Applications/AppleTV.app
if [ -e /Applications/AppleTV.app/Appliances ] || [ -L /Applications/AppleTV.app/Appliances ]; then
    test -d /Applications/AppleTV.app/Appliances
    test -w /Applications/AppleTV.app/Appliances
fi
apt-get check >/dev/null 2>&1
for package in dpkg cydia essential mobilesubstrate beigelist uikittools com.saurik.patcyh; do
    test "$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null)" = "install ok installed"
done
'''
    if a.action == 'connect': return 'set -eu\nid -u\nuname -smr\n'
    if a.action == 'preflight': return (ROOT/'Scripts/device-preflight.sh').read_text()
    if a.action == 'disk': return 'set -eu\ndf -k / /private/var\n'
    if a.action == 'upload':
        return base + gate + f'test -d {d}\ntest -f {d}/BACKUP_VERIFIED\ntest ! -e {d}/candidate.deb\n'
    if a.action == 'backup':
        return base + gate + f'''umask 077
mkdir {d}
cd {d}
package_state > before-state
state=$(cat before-state)
case "$state" in
  'install ok installed '*) test -n {shlex.quote(str(a.rollback_package or ''))} ;;
  '') test ! -e /Applications/Jellyfin.frappliance && test ! -L /Applications/Jellyfin.frappliance
      test ! -e /Applications/AppleTV.app/Appliances/Jellyfin.frappliance && test ! -L /Applications/AppleTV.app/Appliances/Jellyfin.frappliance ;;
  *) exit 73 ;;
esac
if [ -n "$state" ]; then
  test "$(dpkg-query -S /Applications/Jellyfin.frappliance/Info.plist | cut -d: -f1)" = org.jellyfin.atv3
  test "$(dpkg-query -S /Applications/AppleTV.app/Appliances/Jellyfin.frappliance | cut -d: -f1)" = org.jellyfin.atv3
fi
# Require free space before backup: old bundle + 20 MiB on data volume.
used=0
if [ -e /Applications/Jellyfin.frappliance ]; then set -- $(du -sk /Applications/Jellyfin.frappliance); used=$1; fi
set -- $(df -k /private/var | tail -1); free=$4
test "$free" -gt "$((used + 20480))"
set -- var/lib/dpkg/status
for p in Applications/Jellyfin.frappliance Applications/AppleTV.app/Appliances/Jellyfin.frappliance; do
    if [ -e "/$p" ] || [ -L "/$p" ]; then set -- "$@" "$p"; fi
done
tar -czpf before.tar.gz -C / "$@"
tar -tzf before.tar.gz >/dev/null
hash_file before.tar.gz
'''
    if a.action == 'install':
        return base + gate + f'''cd {d}
test -f BACKUP_VERIFIED
test "$(package_state)" = "$(cat before-state)"
test "$(hash_file candidate.deb)" = {shlex.quote(digest)}
test "$(dpkg --field candidate.deb Package)" = org.jellyfin.atv3
test "$(dpkg --field candidate.deb Version)" = {shlex.quote(version)}
set -- $(df -k / | tail -1)
test "$4" -gt 20480
dpkg --info candidate.deb
dpkg --contents candidate.deb
dpkg -i candidate.deb
test "$(package_state)" = {shlex.quote('install ok installed '+version)}
dpkg --audit
'''
    if a.action == 'inspect':
        return base + '''stat_triplet() {
    if stat -c '%u:%g:%a' "$1" >/dev/null 2>&1; then
        stat -c '%u:%g:%a' "$1"
    else
        stat -f '%u:%g:%Lp' "$1"
    fi
}
test "$(readlink /Applications/AppleTV.app/Appliances/Jellyfin.frappliance)" = /Applications/Jellyfin.frappliance
for file in /Applications/Jellyfin.frappliance /Applications/Jellyfin.frappliance/_CodeSignature /Applications/Jellyfin.frappliance/Jellyfin; do
    test "$(stat_triplet "$file")" = 0:0:755
done
for file in /Applications/Jellyfin.frappliance/Info.plist /Applications/Jellyfin.frappliance/_CodeSignature/CodeResources; do
    test "$(stat_triplet "$file")" = 0:0:644
done
dpkg-query -W -f='${Status} ${Version} ${Architecture}\n' org.jellyfin.atv3
dpkg --audit
ls -ldn /Applications/Jellyfin.frappliance /Applications/Jellyfin.frappliance/_CodeSignature
ls -ln /Applications/Jellyfin.frappliance/Jellyfin /Applications/Jellyfin.frappliance/Info.plist /Applications/Jellyfin.frappliance/_CodeSignature/CodeResources
readlink /Applications/AppleTV.app/Appliances/Jellyfin.frappliance
hash_file /Applications/Jellyfin.frappliance/Jellyfin
'''
    removed = '''test ! -e /Applications/Jellyfin.frappliance
test ! -L /Applications/Jellyfin.frappliance
test ! -e /Applications/AppleTV.app/Appliances/Jellyfin.frappliance
test ! -L /Applications/AppleTV.app/Appliances/Jellyfin.frappliance
'''
    if a.action == 'rollback':
        return base + gate + f'''cd {d}
test -f BACKUP_VERIFIED
state=$(cat before-state)
if [ -z "$state" ]; then
    dpkg --remove org.jellyfin.atv3
{removed}else
    test "$(hash_file rollback.deb)" = "$(cat rollback.sha256)"
    test "install ok installed $(dpkg --field rollback.deb Version)" = "$state"
    dpkg -i rollback.deb
    test "$(package_state)" = "$state"
    test "$(readlink /Applications/AppleTV.app/Appliances/Jellyfin.frappliance)" = /Applications/Jellyfin.frappliance
    test -f /Applications/Jellyfin.frappliance/Jellyfin
fi
dpkg --audit
'''
    if a.action == 'uninstall':
        return base + gate + f'test -f {d}/BACKUP_VERIFIED\ndpkg --remove org.jellyfin.atv3\n{removed}dpkg --audit\n'
    if a.action == 'diagnostics': return (ROOT/'Scripts/device-preflight.sh').read_text()
    # Only known log locations; no automatic broad filesystem collection.
    return '''set -u
for directory in /Library/Logs/CrashReporter /var/mobile/Library/Logs/CrashReporter /var/root/Library/Logs/CrashReporter; do
    if [ -d "$directory" ]; then ls -lt "$directory"; fi
done
''' + ('''if [ -f /var/log/syslog ]; then tail -n 400 /var/log/syslog; fi
for directory in /Library/Logs/CrashReporter /var/mobile/Library/Logs/CrashReporter /var/root/Library/Logs/CrashReporter; do
    for file in "$directory"/AppleTV*.crash "$directory"/Lowtide*.crash; do
        if [ -f "$file" ]; then tail -n 300 "$file"; fi
done
done
''' if a.include_sensitive_logs else '')

def execute(a, code, destination):
    with destination.open('xb') as log:
        result = subprocess.run(ssh_args(a)+['sh -s'], input=code.encode(), stdout=log, stderr=log, timeout=180)
    if result.returncode: raise RuntimeError('SSH operation failed; inspect the private local log')

def upload_file(a, source, name):
    target = shlex.quote(remote_dir(a)+'/'+name)
    # stdin transport avoids a device SFTP dependency; noclobber preserves prior attempts.
    with source.open('rb') as data:
        result = subprocess.run(ssh_args(a)+[f'umask 077; set -C; cat > {target}'], stdin=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=180)
    if result.returncode: raise RuntimeError('Upload failed; remote partial file retained; use a new run ID')

def main(argv=None):
    a = parser().parse_args(argv)
    try:
        validate(a)
        digest, version = verify_package(a.package, a.sha256) if a.action in ('upload','install') else (None,None)
        old = verify_package(a.rollback_package) if a.rollback_package else None
        code = script(a,digest,version)
        if not a.execute:
            print('DRY RUN: no SSH or mutation performed. Action:', a.action)
            print(code)
            return 0
        os.umask(0o077)
        a.output.mkdir(parents=True, exist_ok=True)
        # Each invocation is recorded separately and refuses overwrites.
        import time
        log = a.output / (a.run_id+'-'+a.action+'-'+str(time.time_ns())+'.log')
        execute(a,code,log)
        if a.action == 'backup':
            archive = log.with_suffix('.tar.gz')
            with archive.open('xb') as out:
                result = subprocess.run(ssh_args(a)+['cat '+shlex.quote(remote_dir(a)+'/before.tar.gz')], stdout=out, stderr=subprocess.PIPE, timeout=180)
            if result.returncode: raise RuntimeError('Backup download failed')
            expected=log.read_text().splitlines()[-1]
            if hashlib.sha256(archive.read_bytes()).hexdigest()!=expected: raise ValueError('Backup SHA256 mismatch')
            extra=''
            if old:
                upload_file(a,a.rollback_package,'rollback.deb')
                extra=f'test "$(hash_file rollback.deb)" = {shlex.quote(old[0])}\ntest "$(cat before-state)" = {shlex.quote("install ok installed "+old[1])}\nprintf "%s\\n" {shlex.quote(old[0])} > rollback.sha256\n'
            execute(a,'set -eu\n'+HASH+f'cd {shlex.quote(remote_dir(a))}\n'+extra+'touch BACKUP_VERIFIED\n',log.with_suffix('.verified.log'))
        elif a.action == 'upload':
            upload_file(a,a.package,'candidate.deb')
            execute(a,'set -eu\n'+HASH+f'test "$(hash_file {shlex.quote(remote_dir(a)+"/candidate.deb")})" = {shlex.quote(digest)}\n',log.with_suffix('.verified.log'))
        print('Completed action; private evidence:', log)
        print('No host restart performed. Device compatibility remains subject to the checklist.')
        return 0
    except (ValueError, OSError, RuntimeError, subprocess.SubprocessError):
        print('FAIL: deployment step; no subsequent step executed. Check arguments and private local evidence.', file=sys.stderr)
        return 1

if __name__ == '__main__': sys.exit(main())
