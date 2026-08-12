#!/usr/bin/env python3
"""
Patch NGHDL: stop start_server.sh from launching GTKWave after every run.

Symptom
-------
Every ngspice simulation that uses an NGHDL model pops up a GTKWave
window - one per model instance. With a four-node CAN bus that is four
windows on every single simulation run.

Cause
-----
nghdl/src/model_generation.py appends:

    gtkwave <entity>_tb.vcd 2>/dev/null

to the generated start_server.sh.

Fix
---
Comment that line out in the generator, and in any already-generated
start_server.sh files. The VCD is still written, so you can open it
manually with gtkwave whenever you actually want it.

Safe to run more than once. Originals saved with .orig suffix
(or .orig2 if a .orig already exists from an earlier patch).
"""

import glob
import os
import re
import shutil
import sys

GEN = os.path.expanduser(
    "~/Downloads/eSim-2.5/nghdl/src/model_generation.py")

DUT_GLOB = os.path.expanduser(
    "~/nghdl-simulator/src/xspice/icm/ghdl/*/DUTghdl/start_server.sh")


def backup(path):
    dest = path + ".orig"
    if os.path.exists(dest):
        dest = path + ".orig2"
    if not os.path.exists(dest):
        shutil.copy2(path, dest)
    return dest


def patch_generator():
    if not os.path.isfile(GEN):
        print("  SKIP  model_generation.py not found")
        return False

    with open(GEN, "r") as f:
        lines = f.readlines()

    changed = False
    out = []
    for ln in lines:
        # the generator line that writes the gtkwave invocation
        if "gtkwave" in ln and "start_server.write" in ln \
                and not ln.lstrip().startswith("#"):
            indent = ln[:len(ln) - len(ln.lstrip())]
            out.append(indent + "# NGHDL patch: GTKWave auto-launch disabled\n")
            out.append(indent + "# " + ln.lstrip())
            changed = True
        else:
            out.append(ln)

    if not changed:
        print("  OK    model_generation.py (already patched or no match)")
        return True

    b = backup(GEN)
    with open(GEN, "w") as f:
        f.writelines(out)
    print("  DONE  model_generation.py  (backup: %s)" % os.path.basename(b))
    return True


def patch_scripts():
    found = glob.glob(DUT_GLOB)
    if not found:
        print("  (no generated start_server.sh found)")
        return

    for sh in found:
        model = sh.split(os.sep)[-3]
        with open(sh, "r") as f:
            src = f.read()

        if re.search(r"^\s*#\s*gtkwave", src, re.M):
            print("  OK    %s (already patched)" % model)
            continue
        if not re.search(r"^\s*gtkwave", src, re.M):
            print("  OK    %s (no gtkwave line)" % model)
            continue

        b = backup(sh)
        new = re.sub(r"^(\s*)(gtkwave.*)$", r"\1# \2", src, flags=re.M)
        with open(sh, "w") as f:
            f.write(new)
        print("  DONE  %s  (backup: %s)" % (model, os.path.basename(b)))


def main():
    print("Patching generator")
    ok = patch_generator()
    print()
    print("Patching already-generated scripts")
    patch_scripts()
    print()
    print("GTKWave will no longer auto-launch. VCD files are still")
    print("written - open them manually with:  gtkwave <file>.vcd")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
