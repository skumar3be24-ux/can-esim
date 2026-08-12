#!/bin/bash
# ============================================================
# GHDL development loop for the CAN project.
#
#   usage:  ./run.sh <module_name> [stop_time]
#   e.g.:   ./run.sh counter 200us
#
# Expects:
#   vhdl/src/<module>.vhdl      the design
#   vhdl/tb/tb_<module>.vhdl    a self-checking testbench
#
# Produces:
#   vhdl/<module>.vcd           waveform, open with: gtkwave <module>.vcd
#
# Exits non-zero if any assert fails, so it works in regress.sh.
# ============================================================
set -e

M=$1
T=${2:-1ms}

if [ -z "$M" ]; then
    echo "usage: ./run.sh <module_name> [stop_time]"
    exit 2
fi

# always run from the vhdl/ directory regardless of where invoked
cd "$(dirname "$0")/.."

SRC="src/${M}.vhdl"
TB="tb/tb_${M}.vhdl"

[ -f "$SRC" ] || { echo "ERROR: $SRC not found"; exit 2; }
[ -f "$TB"  ] || { echo "ERROR: $TB not found";  exit 2; }

# clean stale library - avoids "unit has changed and must be reanalysed"
rm -f work-obj93.cf

echo "--- analyse ---"
ghdl -a "$SRC" "$TB"

echo "--- elaborate ---"
ghdl -e "tb_${M}"

echo "--- run (stop at ${T}) ---"
ghdl -r "tb_${M}" --stop-time="${T}" --vcd="${M}.vcd" --assert-level=error

echo
echo "PASS: ${M}    waveform -> vhdl/${M}.vcd"
