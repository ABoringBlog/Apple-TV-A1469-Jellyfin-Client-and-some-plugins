#!/usr/bin/env python3
"""Validate that the Clock .deb contains only the intended independent appliance."""
import io
import plistlib
from pathlib import Path
import subprocess
import sys
import tarfile

if len(sys.argv) != 3:
    raise SystemExit("Usage: verify_package.py PACKAGE.deb BUILT_STAGE_CLOCK_BUNDLE")
deb, app = Path(sys.argv[1]), Path(sys.argv[2])
parts = subprocess.check_output(["ar", "t", str(deb)], text=True).splitlines()
assert parts == ["debian-binary", "control.tar.gz", "data.tar.gz"], parts

def get_tar(name):
    buf = subprocess.check_output(["ar", "p", str(deb), name])
    return tarfile.open(fileobj=io.BytesIO(buf), mode="r:gz")

with get_tar("control.tar.gz") as tar:
    members = tar.getmembers()
    assert [m.name for m in members if m.isfile()] == ["control"]
    control = tar.extractfile("control").read().decode()
    assert "Package: org.atv3.clock\n" in control
    assert "Version: 0.1.5\n" in control
    assert "Architecture: iphoneos-arm\n" in control
    assert not any(m.name in {"preinst","postinst","prerm","postrm"} for m in members)
with get_tar("data.tar.gz") as tar:
    files = {m.name: m for m in tar.getmembers() if not m.isdir()}
    prefix = "Applications/Clock.frappliance/"
    expected = {
        "Applications/AppleTV.app/Appliances/Clock.frappliance",
        prefix + "Clock",
        prefix + "Info.plist",
        prefix + "AppIcon.png",
        prefix + "TopRowIcon.png",
        prefix + "English.lproj/InfoPlist.strings",
        prefix + "_CodeSignature/CodeResources",
    }
    assert set(files) == expected, set(files) ^ expected
    symlink = files["Applications/AppleTV.app/Appliances/Clock.frappliance"]
    assert symlink.issym() and symlink.linkname == "/Applications/Clock.frappliance"
    for rel in ["Clock", "Info.plist", "AppIcon.png", "TopRowIcon.png",
                "English.lproj/InfoPlist.strings", "_CodeSignature/CodeResources"]:
        payload = tar.extractfile(files[prefix + rel]).read()
        assert payload == (app / rel).read_bytes(), rel
    assert files[prefix + "Clock"].mode & 0o111
    metadata = plistlib.loads(tar.extractfile(files[prefix+"Info.plist"]).read())
    expected_meta = {
        "CFBundleIdentifier":"org.atv3.clock", "CFBundleVersion":"0.1.5",
        "CFBundleExecutable":"Clock", "NSPrincipalClass":"ClockAppliance",
        "FRApplianceName":"Clock",
    }
    for key, val in expected_meta.items():
        assert metadata.get(key) == val, (key, metadata.get(key))
    assert "Jellyfin" not in " ".join(files), "Clock package must be separate"
print("PASS: Clock 0.1.5 independent signed appliance package, strict payload and metadata")
