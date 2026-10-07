#!/usr/bin/env python3
import io, plistlib, subprocess, sys, tarfile
from pathlib import Path

if len(sys.argv)!=4 or sys.argv[1] not in {"en","zh"}:
    raise SystemExit("Usage: verify_package.py en|zh PACKAGE.deb BUILT_BUNDLE")
lang,deb,app=sys.argv[1],Path(sys.argv[2]),Path(sys.argv[3])
parts=subprocess.check_output(["ar","t",str(deb)],text=True).splitlines()
assert parts==["debian-binary","control.tar.gz","data.tar.gz"],parts

def arc(name):
    data=subprocess.check_output(["ar","p",str(deb),name])
    return tarfile.open(fileobj=io.BytesIO(data),mode="r:gz")

with arc("control.tar.gz") as t:
    control=t.extractfile("control").read().decode()
    assert "Package: org.atv3.internetradio\n" in control
    assert f"Version: 0.3.1-public1-{lang}\n" in control
    assert "Architecture: iphoneos-arm\n" in control
    assert "requires ATV3Bridge running continuously on a Mac" in control

with arc("data.tar.gz") as t:
    m={x.name:x for x in t.getmembers() if not x.isdir()}
    p="Applications/Radio.frappliance/"
    expected={
        "Applications/AppleTV.app/Appliances/Radio.frappliance",
        p+"InternetRadio",p+"Info.plist",p+"AppIcon.png",p+"AppIcon@1080.png",
        p+"English.lproj/InfoPlist.strings",p+"_CodeSignature/CodeResources",
    }
    assert set(m)==expected,set(m)^expected
    link=m["Applications/AppleTV.app/Appliances/Radio.frappliance"]
    assert link.issym() and link.linkname=="/Applications/Radio.frappliance"
    binary=t.extractfile(m[p+"InternetRadio"]).read()
    assert b"192.168." not in binary
    assert b"/var/root/.atv3-radio-bridge-url" in binary
    assert b"/v1/radio/stations?" in binary
    info=plistlib.loads(t.extractfile(m[p+"Info.plist"]).read())
    assert info["CFBundleIdentifier"]=="org.atv3.internetradio"
    assert info["CFBundleVersion"]=="0.3.1"
    locale=t.extractfile(m[p+"English.lproj/InfoPlist.strings"]).read()
    if lang=="en":
        assert b"Internet Radio" in locale and "网络电台".encode() not in locale
    else:
        assert "网络电台".encode() in locale

print("PASS: Radio public package",lang)
