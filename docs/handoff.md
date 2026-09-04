# CAN Protocol Modelling in eSim — Project Handoff

Author: Sourabh Kumar · Repository: `github.com/skumar3be24-ux/can-esim`

---

## What this is

A complete CAN (Controller Area Network) model in eSim: analog physical layer in
ngspice, digital controller in VHDL, joined through eSim's NGHDL mixed-signal
bridge. Four controllers arbitrate over one differential pair.

**Status: the protocol is functionally complete and verified in mixed-signal.**
Remaining work is presentation, not engineering.

---

## Current state (end of Day 43, feature-complete)

### Working and verified

| Layer | What works |
|---|---|
| **Analog PHY** | Differential pair, 45 Ω drivers, 120 Ω termination, tanh comparator, 220 m transmission line. 18-check regression. |
| **Bit timing** | 16 tq per bit, 75% sample point, hard sync, resynchronisation with SJW bounding. |
| **Framing** | Bit stuffing/destuffing, CRC-15 (0x4599), full standard frame assembly and decode. |
| **Bus access** | Non-destructive arbitration, acknowledgement, self-ACK suppression. |
| **Error handling** | CRC/form/stuff/bit error detection, error frames (active and passive), TEC/REC fault confinement, bus-off entry and recovery. |
| **Mixed-signal** | All of the above running as NGHDL models on the analog PHY, 2 and 4 nodes. |

### Headline results

- **CRC-15: 417/417 vectors** match an independently written Python reference
- **Frame generation: 68/68 frames** bit-exact including the stuff boundary
- **Four-node arbitration:** correct winner, and losses exactly **one bit time
  apart** (40.5 / 48.5 / 57.0 µs) matching the identifier bit patterns
- **Non-destructive:** all three losers received the winner's frame
- **Fault confinement:** permanent bus fault drove one node to bus-off at
  5.626 ms while the healthy node was **completely unaffected**
- **No false positives:** zero error frames on clean mixed-signal traffic

Full detail: `docs/verification.md`.

---

## Frozen parameters

Complete list in `docs/phy_spec.md`. The ones that matter:

| Parameter | Value |
|---|---|
| Bit rate | 125 kbit/s (8.000 µs bit time) |
| Time quanta per bit | 16 (tq = 500 ns) |
| VHDL clock | 2.000 MHz |
| SYNC / PROP / PS1 / PS2 | 1 / 5 / 6 / 4 tq |
| Sample point | 12 tq = 75.00% |
| SJW | 4 tq |
| Max bus length | 220 m |
| Driver R_on | 45.0 Ω |
| Termination | 120 Ω × 2 |
| CRC-15 polynomial | 0x4599 |
| Node IDs | A 0x0A5, B 0x123, C 0x2AA, D 0x555 |

**`PROP_SEG = 5 tq` is a measurement, not an assumption** — derived from a
measured round trip of 2.270 µs against a 2.500 µs allowance (9.2% margin).

---

## Repository layout

```
spice/          analog PHY netlists + mixed-signal simulations
  run_phy_regression.sh    18-check PHY regression
  can_mixed.cir            two nodes on the analog bus
  can_4node.cir            four-node arbitration
  can_busoff_perm.cir      fault confinement to bus-off
vhdl/src/       VHDL controller modules (documented)
vhdl/tb/        self-checking testbenches
vhdl/scripts/   run.sh — analyse, elaborate, run one module
nghdl_model/    comment-stripped copies for NGHDL (see its README)
tools/          Python reference models and eSim/NGHDL patches
docs/           phy_spec.md, verification.md, roadmap.md, measurements.md
LOG.md          day-by-day record
```

---

## Six upstream eSim/NGHDL bugs found and fixed

All patched in `tools/`, worth contributing back to the eSim project.

1. **`UnboundLocalError` on Convert** — `attr_microcontroller` used before
   assignment when the project XML lacks a `<microcontroller>` element.
   → `tools/patch_esim_microcontroller.py`
2. **Locale-dependent build failure** — `ghdl -a *.vhdl` relies on glob order;
   under `en_IN.UTF-8` the testbench analysed before its packages.
3. **GTKWave auto-launch** blocking batch runs.
4. **Missing PyQt5** — installed only in eSim's venv, so `nghdl` failed silently.
5. **NGHDL cannot build multi-file VHDL models** — the generated
   `start_server.sh` analysed a fixed list containing only the single uploaded
   file. Any non-trivial model was impossible. Fixed with GHDL make mode
   (`ghdl -i *.vhdl` + `ghdl -m`), which also subsumes bug 2.
   → `tools/patch_nghdl_multifile.py`
6. **The entity parser does not skip comments** — it scans every line for the
   substrings `port` and `end`, so a comment containing either word corrupts the
   port scan and produces a misleading error. Worked around by stripping comments
   from the NGHDL copies.

---

## Known gaps

Listed in full in `docs/verification.md`. The significant ones:

- **No extended (29-bit) identifiers** — standard format only
- **No automatic retransmission** after losing arbitration — the node abandons
  the frame rather than retrying
- **The eSim netlist drives both nodes from one clock.** Resynchronisation
  itself is no longer an untested gap: `tb_skew` sweeps node B from 0 to 6 per
  cent oscillator skew against node A and reception stays correct to 3 per
  cent, three times the derived 0.98 per cent bound. Above the threshold the
  receiver flags an error rather than accepting corrupt data
- **No overload frames**
- **Bit errors during the CRC/ACK delimiter are suppressed** to avoid false
  positives from a registered-signal lag; a precise fix would register the field
  index and compare exactly
- **The comparator has no common-mode input range**, so the model is optimistic
  outside ±7 V where real transceivers saturate

---

## Working practices that paid off

Worth keeping if this is picked up again:

- **Reference models written from the standard, not from the RTL.** If the
  reference is derived from the code, both share any misunderstanding and agree
  while both being wrong.
- **Predictions recorded before measurement**, with errors quoted.
- **Discriminating tests.** For every mechanism, one test that would fail if the
  mechanism were hardwired to succeed — remove the receiver and require
  `ack_err`; remove node A and require B to win.
- **Instrument before theorising.** Several days were lost to confident wrong
  diagnoses that a single cycle-by-cycle trace would have settled in one run.
- **Never reimplement a reference model's inverse in the testbench.** Compare
  against what the model already produces.
- **Check a measurement can distinguish pass from fail.** Two measurements in
  this project returned identical values for the working and broken cases.

---

## Rebuilding from scratch

See `docs/REBUILD.md` — fresh Ubuntu to running mixed-signal simulation,
including the five eSim/NGHDL defects that must be patched first.

---

## Next steps

1. Write up the design report from `docs/verification.md`
2. Optionally close gaps: retransmission, extended identifiers, skewed clocks
3. Contribute the six patches back to the eSim project upstream
