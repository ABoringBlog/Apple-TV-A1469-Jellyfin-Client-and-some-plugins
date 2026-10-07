#!/usr/bin/env python3
"""Check the target artifact, not host @encode values. No device calls."""
import os
from pathlib import Path
import re
import struct
import subprocess
import unittest

BINARY = Path(os.environ['JF_ARM_BUNDLE'])
OBJC = subprocess.check_output(['otool', '-ov', str(BINARY)], text=True)
CLASSES = {}
current = None
active = False
lines = OBJC.splitlines()
for i, line in enumerate(lines):
    if line.startswith('Contents of ') and '__objc_classlist' not in line:
        break
    if re.match(r'^[0-9a-f]{8} 0x', line):
        current = None; active = False
    if line == 'Meta Class':
        current = None; active = False
    match = re.match(r'        name +0x\w+ (.+)', line)
    if match:
        current = match[1]; CLASSES.setdefault(current, {})
    if line.startswith('        baseMethods'):
        active = True
    elif re.match(r'        (baseProtocols|ivars|weakIvarLayout|baseProperties)', line):
        active = False
    if active and current:
        match = re.match(r'            name +0x\w+ (.+)', line)
        if match:
            encoding = re.search(r'types +0x\w+ (.+)', lines[i+1])
            if encoding: CLASSES[current][match[1]] = encoding[1]

class TargetABITests(unittest.TestCase):
    def test_armv7_bundle(self):
        magic, cpu, subtype, kind = struct.unpack_from('<4I', BINARY.read_bytes())
        self.assertEqual((magic, cpu, subtype & 0xffffff, kind), (0xfeedface, 12, 9, 8))

    def test_device_provider_encodings(self):
        expected = {'itemCount': 'l8@0:4', 'itemForRow:': '@12@0:4l8',
                    'titleForRow:': '@12@0:4l8', 'rowSelectable:': 'c12@0:4l8',
                    'heightForRow:': 'f12@0:4l8', 'selectRow:': 'v12@0:4l8'}
        for selector, encoding in expected.items():
            with self.subTest(selector=selector):
                self.assertEqual(CLASSES['JFBRMenu'][selector], encoding)

    def test_device_delegate_encodings(self):
        for selector in ('textDidChange:', 'textDidEndEditing:'):
            self.assertEqual(CLASSES['JFUIController'][selector], 'v12@0:4@8')

    def test_no_private_class_link_dependency(self):
        symbols = subprocess.check_output(['nm', '-u', str(BINARY)], text=True)
        self.assertIsNone(re.search(r'_OBJC_(?:META)?CLASS_\$_BR\w+', symbols))
        self.assertNotIn('BRAppliance', CLASSES)  # protocol must never become a compiled base class

if __name__ == '__main__':
    unittest.main()
