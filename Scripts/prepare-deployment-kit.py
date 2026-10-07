#!/usr/bin/env python3
"""Assemble a new offline kit from the frozen candidate; no device access."""
import hashlib
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
NAME = 'org.jellyfin.atv3_0.4.0-test1_iphoneos-arm.deb'
EXPECTED = '94fde77a0b2d04680dc999cb0c5e92657e4a008fb958da269b981da0b2314738'

def main():
    if len(sys.argv) > 2:
        raise SystemExit('Usage: prepare-deployment-kit.py [NEW_OUTPUT_DIRECTORY]')
    out = Path(sys.argv[1]) if len(sys.argv) == 2 else ROOT / 'build/deployment-phase4e'
    package = ROOT / 'build/package-phase4e-final' / NAME
    if hashlib.sha256(package.read_bytes()).hexdigest() != EXPECTED:
        raise SystemExit('Frozen candidate SHA256 mismatch')
    subprocess.run([sys.executable, str(ROOT / 'Scripts/verify-package.py'), str(package)], check=True)
    out.mkdir(parents=True, exist_ok=False)
    files = {
        NAME: package,
        'Scripts/verify-package.py': ROOT / 'Scripts/verify-package.py',
        'Scripts/device-preflight.sh': ROOT / 'Scripts/device-preflight.sh',
        'docs/phase4e-deployment.md': ROOT / 'docs/phase4e-deployment.md',
        'docs/phase4e-device-validation.md': ROOT / 'docs/phase4e-device-validation.md',
        'package-check.log': ROOT / 'logs/phase4e2-package-check.log',
    }
    for name, source in files.items():
        target = out / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    (out / 'README.txt').write_text(
        'Phase 4E offline deployment kit — WAITING FOR DEVICE\n'
        'Start: shasum -a 256 -c SHA256SUMS\n'
        'Then: python3 Scripts/verify-package.py ' + NAME + '\n'
        'Read docs/phase4e-deployment.md before device operations.\n'
        'The guide uses project-root paths; in this kit the deb is at the root.\n'
        'No SSH, install, restart or real-device validation has been run.\n'
        'Source candidate: build/package-phase4e-final/' + NAME + '\n'
        'Bundle 0.4.0 / deb 0.4.0-test1; retained from Phase 4E package final.\n'
        'Mac signature verification is not device signature trust.\n'
    )
    paths = sorted(p for p in out.rglob('*') if p.is_file())
    (out / 'SHA256SUMS').write_text(''.join(
        hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + p.relative_to(out).as_posix() + '\n'
        for p in paths))
    print('Created offline kit:', out)

if __name__ == '__main__':
    main()
