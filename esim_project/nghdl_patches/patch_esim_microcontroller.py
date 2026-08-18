#!/usr/bin/env python3
"""
Patch eSim 2.5 bug: UnboundLocalError 'attr_microcontroller'
in src/kicadtoNgspice/KicadtoNgspice.py, function callConvert().

Cause
-----
When an existing *_Previous_Values.xml is found (check == 1) but that XML
contains no <microcontroller> element -- true for every project created
before eSim gained microcontroller support, including the bundled
Examples -- the local variable attr_microcontroller is never assigned.
callConvert() then iterates it and raises UnboundLocalError, killing eSim.

Fix
---
Initialise attr_microcontroller to None, and create the element if the
search did not find one. Mirrors exactly what the check == 0 branch does.

Safe to run more than once. Original saved as KicadtoNgspice.py.orig
"""

import shutil
import sys
import os

PATH = os.path.expanduser(
    "~/Downloads/eSim-2.5/src/kicadtoNgspice/KicadtoNgspice.py")

OLD = '''        if check == 1:
            for child in attr_parent:
                if child.tag == "microcontroller":
                    attr_microcontroller = child
'''

NEW = '''        if check == 1:
            attr_microcontroller = None
            for child in attr_parent:
                if child.tag == "microcontroller":
                    attr_microcontroller = child
            if attr_microcontroller is None:
                attr_microcontroller = ET.SubElement(attr_parent,
                                                     "microcontroller")
'''


def main():
    if not os.path.isfile(PATH):
        print("ERROR: file not found:", PATH)
        return 1

    with open(PATH, "r") as f:
        src = f.read()

    if "attr_microcontroller = None" in src:
        print("Already patched - no changes made.")
        return 0

    if OLD not in src:
        print("ERROR: expected code block not found.")
        print("The file may differ from eSim 2.5. No changes made.")
        return 1

    backup = PATH + ".orig"
    shutil.copy2(PATH, backup)

    with open(PATH, "w") as f:
        f.write(src.replace(OLD, NEW, 1))

    print("Patched successfully.")
    print("  file   :", PATH)
    print("  backup :", backup)
    print()
    print("To revert:  cp", backup, PATH)
    return 0


if __name__ == "__main__":
    sys.exit(main())
