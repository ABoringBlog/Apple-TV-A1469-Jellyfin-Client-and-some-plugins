#!/usr/bin/env python3
"""Deployment archive rejection tests; never install or extract package contents."""
import gzip
import importlib.util
import io
import os
import plistlib
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest


def module(name):
    spec = importlib.util.spec_from_file_location(name, 'Scripts/' + name + '.py')
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded

verify = module('verify-package').verify
build = module('build-deb').write_deb
PACKAGE = Path(os.environ.get('JF_PACKAGE', 'build/package-phase4e-final/org.jellyfin.atv3_0.4.0-test1_iphoneos-arm.deb'))
STAGE = PACKAGE.parent / 'stage'
VERSION = verify(PACKAGE)

class PackageTests(unittest.TestCase):
    def test_candidate_and_repeatable_archive(self):
        self.assertEqual(verify(PACKAGE, STAGE / 'Applications/Jellyfin.frappliance'), VERSION)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'repeat.deb'
            build(STAGE, path)
            self.assertEqual(path.read_bytes(), PACKAGE.read_bytes())
            with self.assertRaises(FileExistsError):
                build(STAGE, path)

    def malformed(self, part, change):
        parts = {name: subprocess.check_output(['ar', '-p', str(PACKAGE), name])
                 for name in ('debian-binary', 'control.tar.gz', 'data.tar.gz')}
        output = io.BytesIO()
        with tarfile.open(fileobj=io.BytesIO(parts[part]), mode='r:gz') as source, tarfile.open(fileobj=output, mode='w', format=tarfile.USTAR_FORMAT) as dest:
            for item in source:
                body = source.extractfile(item).read() if item.isfile() else None
                body = change(item, body)
                if body is not None:
                    item.size = len(body)
                dest.addfile(item, io.BytesIO(body) if body is not None else None)
        parts[part] = gzip.compress(output.getvalue(), mtime=0)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'bad.deb'
            with path.open('wb') as dest:
                dest.write(b'!<arch>\n')
                for name, body in parts.items():
                    dest.write(f'{name:<16}{0:<12}{0:<6}{0:<6}{"100644":<8}{len(body):<10}`\n'.encode() + body + (b'\n' if len(body) % 2 else b''))
            with self.assertRaises(ValueError):
                verify(path)

    def test_loader_visible_link_and_payload(self):
        with tarfile.open(fileobj=io.BytesIO(subprocess.check_output(['ar', '-p', str(PACKAGE), 'data.tar.gz'])), mode='r:gz') as archive:
            link = archive.getmember('Applications/AppleTV.app/Appliances/Jellyfin.frappliance')
            self.assertTrue(link.issym())
            self.assertEqual(link.linkname, '/Applications/Jellyfin.frappliance')
            self.assertTrue(archive.getmember(link.linkname.lstrip('/') + '/Jellyfin').isfile())
            self.assertEqual((link.uid, link.gid), (0, 0))

    def test_missing_loader_visible_entry(self):
        def change(item, body):
            if item.issym(): item.name = 'Applications/Jellyfin-unreachable.frappliance'
            return body
        self.malformed('data.tar.gz', change)

    def test_principal_and_loader_metadata(self):
        for key, value in [('NSPrincipalClass', 'BRAppliance'), ('CFBundleIdentifier', ''),
                           ('CFBundleExecutable', 'Missing'), ('CFBundlePackageType', 'APPL'),
                           ('CFBundleName', ''), ('FRApplianceName', ''),
                           ('CFBundleSupportedPlatforms', ['MacOSX']),
                           ('FRAppliancePreferedOrderValue', '5'), ('FRAppliancePreferedOrderValue', True)]:
            with self.subTest(key=key, value=value):
                def change(item, body):
                    if item.name.endswith('/Info.plist'):
                        metadata = plistlib.loads(body); metadata[key] = value
                        return plistlib.dumps(metadata)
                    return body
                self.malformed('data.tar.gz', change)

    def test_loader_localized_name(self):
        if tuple(int(v) for v in VERSION.split('-')[0].split('.')) < (0, 5, 1):
            self.skipTest('historical candidate predates loader localization fix')
        def change(item, body):
            if item.name.endswith('/InfoPlist.strings'):
                return plistlib.dumps({'CFBundleName': ''})
            return body
        self.malformed('data.tar.gz', change)

    def test_wrong_owner(self):
        def change(item, body):
            item.uid = 501
            return body
        self.malformed('data.tar.gz', change)

    def test_writable_binary(self):
        def change(item, body):
            if item.name.endswith('/Jellyfin'):
                item.mode = 0o777
            return body
        self.malformed('data.tar.gz', change)

    def test_wrong_link(self):
        def change(item, body):
            if item.issym():
                item.linkname = '/tmp/wrong'
            return body
        self.malformed('data.tar.gz', change)

    def test_path_escape(self):
        def change(item, body):
            if item.name.endswith('/Info.plist'):
                item.name = '../../Info.plist'
            return body
        self.malformed('data.tar.gz', change)

    def test_wrong_architecture(self):
        def change(item, body):
            if item.name.endswith('/Jellyfin'):
                return b'not ARMv7'
            return body
        self.malformed('data.tar.gz', change)

    def test_version_mismatch(self):
        self.malformed('control.tar.gz', lambda item, body: body.replace(VERSION.encode(), b'9.0.0-test1') if body else body)

    def test_maintainer_script(self):
        def change(item, body):
            if item.name == 'control':
                item.name = 'postinst'
            return body
        self.malformed('control.tar.gz', change)

if __name__ == '__main__':
    unittest.main()
