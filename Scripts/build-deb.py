#!/usr/bin/env python3
"""Small offline ar + gzip/ustar writer; explicit root ownership, no external packager."""
import gzip
import io
from pathlib import Path
import sys
import tarfile


def tar_bytes(root, paths):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode='w', format=tarfile.USTAR_FORMAT) as archive:
        for path in sorted(paths):
            info = archive.gettarinfo(str(path), arcname=str(path.relative_to(root)))
            info.uid = info.gid = 0
            info.uname, info.gname, info.mtime = 'root', 'wheel', 0
            if info.issym():
                info.mode = 0o777
            if info.isfile():
                with path.open('rb') as source:
                    archive.addfile(info, source)
            else:
                archive.addfile(info)
    return gzip.compress(output.getvalue(), mtime=0)


def write_deb(stage, output):
    stage = Path(stage)
    control = stage / 'DEBIAN'
    pieces = [('debian-binary', b'2.0\n'),
              ('control.tar.gz', tar_bytes(control, list(control.rglob('*')))),
              ('data.tar.gz', tar_bytes(stage, [p for p in stage.rglob('*') if control not in p.parents and p != control]))]
    with Path(output).open('xb') as destination:
        destination.write(b'!<arch>\n')
        for name, data in pieces:
            header = f'{name:<16}{0:<12}{0:<6}{0:<6}{"100644":<8}{len(data):<10}`\n'.encode('ascii')
            if len(header) != 60:
                raise ValueError('ar header length exceeded')
            destination.write(header + data + (b'\n' if len(data) % 2 else b''))

if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('Usage: build-deb.py STAGE NEW_OUTPUT')
    write_deb(*sys.argv[1:])
