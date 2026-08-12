#!/bin/bash
# ============================================================
# GHDL development loop for the CAN project.
#
#   usage:  ./run.sh <module_name> [stop_time]
#   e.g.:   ./run.sh frame_tx 40us
#
# Expects:
#   vhdl/src/<module>.vhdl      the design (plus any submodules
#                               it uses, also in src/)
#   vhdl/tb/tb_<module>.vhdl    a self-checking testbench
#
# Produces:
#   vhdl/<module>.vcd           waveform: gtkwave <module>.vcd
#
# Uses GHDL "make" mode (-i then -m) rather than analysing files
# by hand. -i indexes every source file; -m then works out the
# dependency order itself and analyses only what is needed.
#
# This matters: VHDL requires a unit to be analysed before anything
# that references it, and hand-ordering breaks as soon as a design
# has several submodules. can_node will have eight.
#
# Exits non-zero if any assert fails, so regress.sh can use it.
# ============================================================
set -e

M=$1
T=${2:-1ms}

if [ -z "$M" ]; then
    echo "usage: ./run.sh <module_name> [stop_time]"
    exit 2
fi

# always operate from the vhdl/ directory, wherever we were invoked
cd "$(dirname "$0")/.."

SRC="src/${M}.vhdl"
TB="tb/tb_${M}.vhdl"

[ -f "$SRC" ] || { echo "ERROR: $SRC not found"; exit 2; }
[ -f "$TB"  ] || { echo "ERROR: $TB not found";  exit 2; }

# clean library so stale units cannot mask a real error
rm -f work-obj93.cf

echo "--- index sources ---"
ghdl -i src/*.vhdl "$TB"

echo "--- make (analyse in dependency order + elaborate) ---"
ghdl -m "tb_${M}"

echo "--- run (stop at ${T}) ---"
ghdl -r "tb_${M}" --stop-time="${T}" --vcd="${M}.vcd" --assert-level=error

echo
echo "PASS: ${M}    waveform -> vhdl/${M}.vcd"
