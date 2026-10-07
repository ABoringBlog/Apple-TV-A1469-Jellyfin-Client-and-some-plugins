#!/usr/bin/env python3
"""Create an immutable offline deployment kit; no SSH or installation."""
import hashlib
from pathlib import Path
import shutil
import subprocess
import sys

ROOT=Path(__file__).resolve().parent.parent
NAME='org.jellyfin.atv3_0.5.0-predevice1_iphoneos-arm.deb'
SHA='214fe2607b19293dea4dba64c6bc066b6bf17a6a1253e54cf03eab8d812bcae9'

def main():
    if len(sys.argv)>2: raise SystemExit('Usage: prepare-freeze-kit.py [NEW_DIRECTORY]')
    out=Path(sys.argv[1]) if len(sys.argv)==2 else ROOT/'build/deployment-pre-device-final'
    source=ROOT/'build/package-pre-device-final'/NAME
    if hashlib.sha256(source.read_bytes()).hexdigest()!=SHA: raise SystemExit('Candidate SHA256 mismatch')
    subprocess.run([sys.executable,str(ROOT/'Scripts/verify-package.py'),str(source)],check=True)
    out.mkdir(parents=True,exist_ok=False)
    files=['Scripts/device-preflight.sh','Scripts/device-deploy.py','Scripts/verify-package.py',
           'docs/pre-device-freeze.md','docs/device-validation-checklist.md','docs/deployment-tooling.md',
           'docs/playback-architecture.md','docs/subtitle-architecture.md','docs/phase4e-deployment.md',
           'docs/phase4e-device-validation.md']
    shutil.copy2(source,out/NAME)
    for name in files:
        target=out/name; target.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(ROOT/name,target)
    for name in ('pre-device-package-tests.log','pre-device-reproducibility.log'):
        shutil.copy2(ROOT/'logs'/name,out/name)
    (out/'README.txt').write_text(
        'Pre-Device Freeze 0.5.0-predevice1\n'
        'Verify: shasum -a 256 -c SHA256SUMS\n'
        'Inspect: python3 Scripts/verify-package.py '+NAME+'\n'
        'Read docs/deployment-tooling.md and docs/device-validation-checklist.md.\n'
        'The candidate is at this kit root; replace project build paths accordingly.\n'
        'All device results NOT RUN. No SSH, installation or restart performed.\n'
        'Phase 4E documents are retained historical instructions for 0.4.0.\n'
        'No real player backend is installed; provisional models are not device evidence.\n')
    (out/'SHA256SUMS').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.relative_to(out).as_posix()+'\n' for p in sorted(out.rglob('*')) if p.is_file()))
    print('Created:',out)

if __name__=='__main__': main()
