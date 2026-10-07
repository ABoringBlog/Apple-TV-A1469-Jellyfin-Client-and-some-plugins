#!/usr/bin/env python3
import io, plistlib, subprocess, sys, tarfile
from pathlib import Path
if len(sys.argv) != 4 or sys.argv[1] not in {"en","zh"}:
    raise SystemExit("Usage: verify_package.py en|zh PACKAGE.deb BUILT_BUNDLE")
lang, deb, app = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
parts = subprocess.check_output(["ar","t",str(deb)], text=True).splitlines()
assert parts == ["debian-binary","control.tar.gz","data.tar.gz"], parts
def arc(name):
    data = subprocess.check_output(["ar","p",str(deb),name])
    return tarfile.open(fileobj=io.BytesIO(data), mode="r:gz")
with arc("control.tar.gz") as t:
    control = t.extractfile("control").read().decode()
    assert "Package: org.atv3.weather\n" in control
    assert f"Version: 1.0.0-public1-{lang}\n" in control
    assert "requires ATV3Bridge running continuously on a Mac" in control
with arc("data.tar.gz") as t:
    m = {x.name:x for x in t.getmembers() if not x.isdir()}
    p = "Applications/Weather.frappliance/"
    expected = {
        "Applications/AppleTV.app/Appliances/Weather.frappliance",
        p+"Weather", p+"Info.plist", p+"AppIcon.png", p+"AppIcon@1080.png",
        p+"TopRowIcon.png", p+"TopRowIcon@1080.png",
        p+"English.lproj/InfoPlist.strings", p+"_CodeSignature/CodeResources",
    }
    assert set(m) == expected, set(m)^expected
    link = m["Applications/AppleTV.app/Appliances/Weather.frappliance"]
    assert link.issym() and link.linkname == "/Applications/Weather.frappliance"
    binary = t.extractfile(m[p+"Weather"]).read()
    assert b"192.168." not in binary
    assert b"/var/root/.atv3-weather-bridge-url" in binary
    info = plistlib.loads(t.extractfile(m[p+"Info.plist"]).read())
    assert info["CFBundleIdentifier"] == "org.atv3.weather"
    assert info["CFBundleVersion"] == "1.0.0"
print("PASS: Weather public package", lang)
