#!/usr/bin/env bash
# CAN PHY regression - re-runs every Day 13-20 netlist and checks the
# key measurements against their frozen values.
#
# Usage:  cd ~/Documents/CAN_project/spice && ./run_phy_regression.sh
#
# Exit 0 = all PASS, exit 1 = at least one FAIL.
#
# Tolerances are deliberately tight (0.1% on voltages, 1% on times).
# If any of these drift, a model or parameter changed and the frozen
# spec in docs/phy_spec.md is no longer valid.

set -u
cd "$(dirname "$0")"

PASS=0
FAIL=0

# check <name> <measured> <expected> <tolerance_fraction>
check() {
  local name="$1" meas="$2" exp="$3" tol="$4"
  if [ -z "$meas" ]; then
    printf '  %-34s FAIL  (no measurement found)\n' "$name"
    FAIL=$((FAIL+1)); return
  fi
  local ok
  ok=$(awk -v m="$meas" -v e="$exp" -v t="$tol" 'BEGIN{
    d = m - e; if (d < 0) d = -d;
    lim = e; if (lim < 0) lim = -lim;
    lim = lim * t; if (lim < 1e-9) lim = 1e-9;
    print (d <= lim) ? "1" : "0";
  }')
  if [ "$ok" = "1" ]; then
    printf '  %-34s PASS  %s\n' "$name" "$meas"
    PASS=$((PASS+1))
  else
    printf '  %-34s FAIL  got %s expected %s\n' "$name" "$meas" "$exp"
    FAIL=$((FAIL+1))
  fi
}

# grab <logfile> <measname>  -> prints the value
grab() {
  grep -m1 "^$2 " "$1" 2>/dev/null | awk '{print $3}'
}

run_cir() {
  ngspice -b "$1" > "/tmp/phy_$(basename "$1" .cir).log" 2>&1
}

echo ""
echo "=========================================="
echo " CAN PHY REGRESSION"
echo " against frozen spec docs/phy_spec.md"
echo "=========================================="

# ---------- Day 17: transmission line ----------
echo ""
echo "Day 17 - transmission line, 220 m"
run_cir phy_tline.cir
L=/tmp/phy_phy_tline.log
check "propagation delay"      "$(grab $L t_prop)"   1.113567e-06 0.01
check "TX to far RX"           "$(grab $L t_txrx)"   1.135200e-06 0.01
check "near-end Vdiff dominant" "$(grab $L vda_dom)" 1.996406e+00 0.001
check "far-end Vdiff dominant"  "$(grab $L vdb_dom)" 1.991271e+00 0.001

# ---------- Day 18: reflections ----------
echo ""
echo "Day 18 - reflection coefficients"
run_cir phy_reflection.cir
L=/tmp/phy_phy_reflection.log
# four runs in sequence; pull them in order
mapfile -t PKS < <(grep "^vdb_pk " "$L" | awk '{print $3}')
check "Gamma=0    peak (120 ohm)" "${PKS[0]:-}" 1.996406e+00 0.001
check "Gamma=+1   peak (open)"    "${PKS[1]:-}" 3.992809e+00 0.001
check "Gamma=+.786 peak (1k)"     "${PKS[2]:-}" 3.565009e+00 0.001
check "Gamma=-.333 peak (60 ohm)" "${PKS[3]:-}" 1.330937e+00 0.001

# ---------- Day 19: common-mode rejection ----------
echo ""
echo "Day 19 - common-mode rejection (corrected)"
run_cir phy_cmrr2.cir
L=/tmp/phy_phy_cmrr2.log
mapfile -t VDB < <(grep "^vdb " "$L" | awk '{print $3}')
mapfile -t VCM < <(grep "^vcmb " "$L" | awk '{print $3}')
# differential must be identical at every offset
check "Vdiff at -12 V offset" "${VDB[0]:-}" 1.992825e+00 0.001
check "Vdiff at   0 V offset" "${VDB[3]:-}" 1.992825e+00 0.001
check "Vdiff at +12 V offset" "${VDB[6]:-}" 1.992825e+00 0.001
# common mode must track the offset
check "CM at -12 V offset"    "${VCM[0]:-}" 1.444648e+01 0.01
check "CM at +12 V offset"    "${VCM[6]:-}" -9.446477e+00 0.01

# ---------- Day 20: multi-bit-rate ----------
echo ""
echo "Day 20 - multi-bit-rate over 220 m"
run_cir phy_bitrate.cir
L=/tmp/phy_phy_bitrate.log
check "1 Mbit/s  Vdiff at sample"   "$(grab $L vdb_1m)"  1.495512e-07 0.10
check "500 kbit/s Vdiff at sample"  "$(grab $L vdb_500)" 1.996406e+00 0.001
check "125 kbit/s Vdiff at sample"  "$(grab $L vdb_125)" 1.996406e+00 0.001
check "far-end arrival time"        "$(grab $L t_arrive)" 1.113853e-05 0.01

# 1 Mbit/s must READ RECESSIVE - this is a logic check, not a tolerance check
RX1M="$(grab $L rxb_1m)"
if awk -v v="${RX1M:-0}" 'BEGIN{exit !(v > 4.5)}'; then
  printf '  %-34s PASS  %s (bit correctly missed)\n' "1 Mbit/s RX = recessive" "$RX1M"
  PASS=$((PASS+1))
else
  printf '  %-34s FAIL  got %s expected ~5.0\n' "1 Mbit/s RX = recessive" "${RX1M:-none}"
  FAIL=$((FAIL+1))
fi

# ---------- summary ----------
echo ""
echo "=========================================="
printf " PASS: %d   FAIL: %d\n" "$PASS" "$FAIL"
if [ "$FAIL" -eq 0 ]; then
  echo " PHY spec is intact."
  echo "=========================================="
  exit 0
else
  echo " PHY SPEC VIOLATED - a model or parameter"
  echo " changed. Do not proceed until resolved."
  echo "=========================================="
  exit 1
fi
