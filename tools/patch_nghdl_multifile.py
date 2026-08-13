#!/usr/bin/env python3
"""
Patch NGHDL's model_generation.py to support MULTI-FILE VHDL models.

THE PROBLEM
-----------
The generated start_server.sh analyses a fixed list of files:

    ghdl -a Utility_Package.vhdl &&
    ghdl -a Vhpi_Package.vhdl &&
    ghdl -a sock_pkg.vhdl &&
    ghdl -a <uploaded_file>.vhdl &&
    ghdl -a <uploaded_file>_tb.vhdl &&
    ghdl -e -Wl,ghdlserver.o <uploaded_file>_tb

Only the ONE uploaded file is analysed. Any model split across
several VHDL files - an entity that instantiates submodules -
cannot be built, because the dependencies are never compiled.

This is a hard limitation for any non-trivial model. A CAN
controller, for instance, is naturally eight files.

(The three explicit package lines are themselves a previous patch
of mine, replacing "ghdl -a *.vhdl". That fixed a locale-dependent
glob-ordering bug: under en_IN.UTF-8 the shell expanded the glob
with the testbench first, so it was analysed before the packages it
depends on, producing a misleading "vhpi_foreign has not been
analyzed" error. Both problems disappear with the fix below.)

THE FIX
-------
Use GHDL's make mode, which builds a dependency graph and analyses
in the correct order regardless of filename or locale:

    ghdl -i *.vhdl &&
    ghdl -m -Wl,ghdlserver.o <uploaded_file>_tb &&

Verified before writing this patch:
  - "ghdl -e" after only "ghdl -i" FAILS: unit has not been analyzed
  - "ghdl -m" resolves an eight-file dependency chain automatically
  - "ghdl -m" accepts -Wl, flags, so it can still link ghdlserver.o

This is strictly more general than the current behaviour: a
single-file model still works, and multi-file models now work too.

USAGE
-----
    python3 patch_nghdl_multifile.py
    python3 patch_nghdl_multifile.py --revert
"""

import os
import shutil
import sys

TARGET = os.path.expanduser(
    "~/Downloads/eSim-2.5/nghdl/src/model_generation.py")
BACKUP = TARGET + ".premultifile"

OLD_LINUX = '''        start_server.write("ghdl -a Utility_Package.vhdl &&\\n")
        start_server.write("ghdl -a Vhpi_Package.vhdl &&\\n")
        start_server.write("ghdl -a sock_pkg.vhdl &&\\n")
        start_server.write("ghdl -a " + self.fname + " &&\\n")
        start_server.write(
            "ghdl -a " + self.fname.split('.')[0] + "_tb.vhdl  &&\\n"
        )'''

NEW_LINUX = '''        # ---- multi-file support ----
        # GHDL make mode: import every source in the directory, then
        # let GHDL work out the dependency order itself. Replaces a
        # fixed list that only ever analysed the single uploaded
        # file, which made multi-file models impossible, and also
        # removes the locale-dependent glob-ordering bug.
        start_server.write("ghdl -i *.vhdl &&\\n")'''

OLD_E_NT = '''            start_server.write("ghdl -e -Wl,ghdlserver.o " +
                               "-Wl,libws2_32.a " +
                               self.fname.split('.')[0] + "_tb &&\\n")'''

NEW_E_NT = '''            start_server.write("ghdl -m -Wl,ghdlserver.o " +
                               "-Wl,libws2_32.a " +
                               self.fname.split('.')[0] + "_tb &&\\n")'''

OLD_E_NIX = '''            start_server.write("ghdl -e -Wl,ghdlserver.o " +
                               self.fname.split('.')[0] + "_tb &&\\n")'''

NEW_E_NIX = '''            start_server.write("ghdl -m -Wl,ghdlserver.o " +
                               self.fname.split('.')[0] + "_tb &&\\n")'''


def revert():
    if not os.path.exists(BACKUP):
        print("No backup found at %s" % BACKUP)
        return 1
    shutil.copy(BACKUP, TARGET)
    print("Reverted %s" % TARGET)
    return 0


def apply():
    if not os.path.exists(TARGET):
        print("ERROR: %s not found" % TARGET)
        return 1

    src = open(TARGET).read()

    if 'ghdl -i *.vhdl' in src:
        print("Already patched.")
        return 0

    if not os.path.exists(BACKUP):
        shutil.copy(TARGET, BACKUP)
        print("Backup written to %s" % BACKUP)

    n = 0
    for old, new, label in (
            (OLD_LINUX, NEW_LINUX, "analysis lines -> ghdl -i"),
            (OLD_E_NT,  NEW_E_NT,  "windows elaborate -> ghdl -m"),
            (OLD_E_NIX, NEW_E_NIX, "linux elaborate -> ghdl -m")):
        if old in src:
            src = src.replace(old, new, 1)
            print("  patched: %s" % label)
            n += 1
        else:
            print("  NOT FOUND: %s" % label)

    if n == 0:
        print("Nothing patched - the file may have changed upstream.")
        return 1

    open(TARGET, 'w').write(src)
    print("Patched %s (%d of 3 substitutions)" % (TARGET, n))
    return 0


if __name__ == '__main__':
    if '--revert' in sys.argv:
        sys.exit(revert())
    sys.exit(apply())
