#!/usr/bin/env python3
"""
Patch NGHDL bug: generated start_server.sh analyses VHDL in shell glob
order, which is locale dependent and violates VHDL dependency order.

Symptom
-------
Simulating any NGHDL model fails with, e.g.:

    customblock_tb.vhdl:10:18:error: unit package "vhpi_foreign"
                                     has not been analyzed
    ...
    Connect- Error:Tried to connect server on port,failed...giving up

Cause
-----
nghdl/src/model_generation.py writes:

    ghdl -i *.vhdl &&
    ghdl -a *.vhdl &&

VHDL requires a package to be analysed before any unit that uses it.
The generated testbench <entity>_tb.vhdl depends on Utility_Package,
Vhpi_Package and sock_pkg. Whether the glob happens to place those
first depends entirely on locale collation:

    LC_ALL=C          -> Utility_Package Vhpi_Package customblock
                         customblock_tb sock_pkg
    en_IN.UTF-8 etc.  -> customblock_tb customblock sock_pkg
                         Utility_Package Vhpi_Package

Under any UTF-8 locale the testbench is analysed first and every
dependency is reported missing. Even under C the testbench precedes
sock_pkg, so the glob approach is unsound in general.

Fix
---
Analyse the three support packages explicitly, in dependency order,
before the entity and its testbench (which model_generation.py already
emits on the following two lines).

Resulting order:
    Utility_Package -> Vhpi_Package -> sock_pkg -> <entity> -> <entity>_tb

This script also repairs any already-generated start_server.sh files so
existing models work without regeneration.

Safe to run more than once. Originals saved with .orig suffix.
"""

import glob
import os
import shutil
import sys

GEN = os.path.expanduser(
    "~/Downloads/eSim-2.5/nghdl/src/model_generation.py")

DUT_GLOB = os.path.expanduser(
    "~/nghdl-simulator/src/xspice/icm/ghdl/*/DUTghdl/start_server.sh")

GEN_OLD = '''        start_server.write("ghdl -i *.vhdl &&\\n")
        start_server.write("ghdl -a *.vhdl &&\\n")
'''

GEN_NEW = '''        start_server.write("ghdl -a Utility_Package.vhdl &&\\n")
        start_server.write("ghdl -a Vhpi_Package.vhdl &&\\n")
        start_server.write("ghdl -a sock_pkg.vhdl &&\\n")
'''

SH_OLD = """ghdl -i *.vhdl &&
ghdl -a *.vhdl &&
"""

SH_NEW = """ghdl -a Utility_Package.vhdl &&
ghdl -a Vhpi_Package.vhdl &&
ghdl -a sock_pkg.vhdl &&
"""


def patch_file(path, old, new, label):
    if not os.path.isfile(path):
        print("  SKIP  %s (not found)" % label)
        return False

    with open(path, "r") as f:
        src = f.read()

    if new.strip().splitlines()[0] in src:
        print("  OK    %s (already patched)" % label)
        return True

    if old not in src:
        print("  WARN  %s (expected block not found, unchanged)" % label)
        return False

    shutil.copy2(path, path + ".orig")
    with open(path, "w") as f:
        f.write(src.replace(old, new, 1))
    print("  DONE  %s  (backup: %s.orig)" % (label, os.path.basename(path)))
    return True


def main():
    print("Patching NGHDL generator")
    ok = patch_file(GEN, GEN_OLD, GEN_NEW, "model_generation.py")

    print()
    print("Repairing already-generated start_server.sh files")
    found = glob.glob(DUT_GLOB)
    if not found:
        print("  (none found)")
    for sh in found:
        model = sh.split(os.sep)[-3]
        patch_file(sh, SH_OLD, SH_NEW, "start_server.sh [%s]" % model)

    print()
    if ok:
        print("Generator patched. Models generated from now on will")
        print("analyse VHDL in correct dependency order.")
    else:
        print("Generator NOT patched - check the file manually.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
