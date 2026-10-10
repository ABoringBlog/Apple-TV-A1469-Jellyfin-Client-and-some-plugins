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
    assert "Package: org.atv3.cloudtune\n" in control
    assert f"Version: 1.1.0-public2-{lang}\n" in control
    assert "Architecture: iphoneos-arm\n" in control
    assert "requires a Mac CloudTune Bridge" in control

with arc("data.tar.gz") as t:
    m={x.name:x for x in t.getmembers() if not x.isdir()}
    p="Applications/CloudTune.frappliance/"
    expected={
        "Applications/AppleTV.app/Appliances/CloudTune.frappliance",
        p+"CloudTune",p+"Info.plist",p+"AppIcon.png",p+"AppIcon@1080.png",
        p+"English.lproj/InfoPlist.strings",p+"_CodeSignature/CodeResources",
    }
    assert set(m)==expected,set(m)^expected
    link=m["Applications/AppleTV.app/Appliances/CloudTune.frappliance"]
    assert link.issym() and link.linkname=="/Applications/CloudTune.frappliance"

    binary=t.extractfile(m[p+"CloudTune"]).read()
    assert b"192.168." not in binary
    assert b"/Users/" not in binary
    assert b"org.atv3.neteasemusic" not in binary
    assert b"ATVNetEaseMusicController" not in binary
    assert b"com.netease" not in binary
    assert b"/var/root/.atv3-cloudtune-bridge-url" in binary
    assert b"org.atv3.cloudtune" in binary
    assert b"ATVCloudTuneController" in binary
    assert b"CloudTuneAppliance" in binary
    assert b"CloudTune" in binary
    assert b"BRTextEntryController" in binary
    assert b"cloudtuneOpenSearchEditor" in binary
    assert b"cloudtuneTimerFire:" in binary

    info=plistlib.loads(t.extractfile(m[p+"Info.plist"]).read())
    assert info["CFBundleIdentifier"]=="org.atv3.cloudtune"
    assert info["CFBundleExecutable"]=="CloudTune"
    assert info["CFBundleVersion"]=="1.1.0"
    assert info["FRApplianceIdentifier"]=="cloudtune"

    locale=t.extractfile(m[p+"English.lproj/InfoPlist.strings"]).read()
    if lang=="en":
        assert b"CloudTune" in locale and "云律音乐".encode() not in locale
    else:
        assert "云律音乐".encode() in locale

print("PASS: CloudTune public package",lang)
