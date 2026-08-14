# CAN Protocol — Circuit-Level Modelling & Verification in eSim

Complete Controller Area Network node — physical layer and protocol
controller — modelled and verified at circuit level using open-source EDA
tools.

**FOSSEE eSim Semester Long Internship, Autumn 2026 — Task 2**

---

## What this is

A mixed-signal simulation of a CAN bus in which:

- The **physical layer** is a real analog circuit in ngspice — differential
  CANH/CANL pair, 120 Ω termination at both ends, switch-based drivers with
  45 Ω on-resistance, bias network, bus capacitance and a differential
  comparator
- The **protocol controller** is VHDL — bit timing with resynchronisation,
  framing, bit stuffing, CRC-15, arbitration, acknowledgement, error frames
  and fault confinement
- The two are joined through **NGHDL**, which compiles VHDL into an XSPICE
  code model that ngspice can instantiate

CAN was chosen deliberately over UART/SPI/I²C. Its central mechanism —
non-destructive bitwise arbitration — is a direct consequence of the bus being
an electrical wired-AND: recessive is passive, dominant is actively driven and
physically overrides it. A node drives a recessive level, reads the actual
voltage back off the wire, and withdraws if it reads dominant. That cannot be
demonstrated without a correct analog bus model, which makes this inherently a
mixed-signal project rather than a digital one with decorative analog attached.

---

## Status: complete

| Phase | Content | State |
|---|---|---|
| 0 | Environment, NGHDL de-risking | ✅ |
| 1 | VHDL competency | ✅ |
| 2 | Analog physical layer | ✅ |
| 3 | Bit timing & synchronisation | ✅ |
| 4 | Transmit path | ✅ |
| 5 | Receive path | ✅ |
| 6 | Error management | ✅ |
| 7 | Node integration | ✅ |
| 8 | Multi-node & arbitration | ✅ |
| 9 | Mixed-signal & fault studies | ✅ |
| 10 | Verification campaign | ✅ |
| 11 | eSim project & submission | ✅ |

Mixed-signal integration was pulled forward from its planned Day 59 to Day 32
to retire the project's largest risk early. See `LOG.md` for the day-by-day
record.

---

## Headline results

| Result | Measurement |
|---|---|
| **CRC-15** | 417/417 vectors match an independently written reference |
| **Frame generation** | 68/68 frames bit-exact, including stuff-bit positions |
| **Four-node arbitration** | correct winner; losers withdrew at 40.5 / 48.5 / 57.0 µs — exactly one bit time apart, in the order their identifiers predict |
| **Non-destructive** | all three losers received the winner's frame |
| **Fault confinement** | a permanent bus short drove one node to bus-off at 5.626 ms while a healthy node on the same wire was unaffected |
| **Clean traffic** | zero false error frames across the mixed-signal runs |
| **PROP_SEG** | derived from a *measured* 2.270 µs round trip against 2.500 µs allowed — 9% margin |

Arbitration is visible in the analog waveform: the bus differential sits at
2.85 V while both nodes drive dominant (two 45 Ω drivers in parallel = 22.5 Ω),
then settles to 2.00 V when one withdraws.

Full detail: **`docs/verification.md`** — 75 tests with predicted and measured
values.

---

## Key design parameters

| Parameter | Value |
|---|---|
| Bit rate | 125 kbit/s |
| Nominal bit time | 8.000 µs |
| Time quanta per bit | 16 (500 ns each) |
| Segments SYNC / PROP / PS1 / PS2 | 1 / 5 / 6 / 4 tq |
| Sample point | 75.00% (tq 12) |
| SJW | 4 tq |
| Oscillator tolerance (derived) | 0.98% |
| Max bus length (derived) | 220 m |
| Dominant levels | CANH 3.5 V, CANL 1.5 V, Vdiff 2.0 V |
| Recessive levels | both 2.5 V, Vdiff 0 V |
| Driver on-resistance | 45.0 Ω |
| Termination | 120 Ω ×2 → 60 Ω differential |
| CRC-15 polynomial | 0x4599 |
| Identifiers | A 0x0A5, B 0x123, C 0x2AA, D 0x555 |

Frozen in `docs/phy_spec.md`, with an 18-check regression script that verifies
every one of them.

---

## Repository layout

```
docs/            phy_spec.md      frozen parameters + model limitations
                 verification.md  every test, predicted vs measured
                 measurements.md  full day-by-day results
                 roadmap.md       the original 86-day plan
                 handoff.md       context for resuming work
                 schematics/      eSim schematic export
                 waveforms/       simulation figures
vhdl/src         10 design modules
vhdl/tb          self-checking testbenches
vhdl/scripts     run.sh
spice/           analog PHY netlists + mixed-signal simulations
                 run_phy_regression.sh  18-check PHY regression
nghdl_model/     comment-stripped VHDL for the NGHDL build
esim_project/    the complete eSim project (schematic, netlists, VHDL)
tools/           Python reference models and eSim/NGHDL patches
LOG.md           daily development record
```

---

## Six upstream eSim/NGHDL bugs found and patched

All in `tools/`, and worth contributing back:

1. **`UnboundLocalError` on Convert** — `attr_microcontroller` used before
   assignment when the project XML lacks a `<microcontroller>` element
2. **Locale-dependent build failure** — `ghdl -a *.vhdl` relies on glob order;
   under `en_IN.UTF-8` the testbench analysed before its packages
3. **GTKWave auto-launch** blocking batch runs
4. **Missing PyQt5** — installed only in eSim's venv, so `nghdl` failed silently
5. **NGHDL cannot build multi-file VHDL models** — the generated
   `start_server.sh` analysed only the single uploaded file, making any
   non-trivial model impossible. Fixed with GHDL make mode (`ghdl -i` +
   `ghdl -m`), which also subsumes bug 2
6. **The entity parser does not skip comments** — it scans every line for
   `port` and `end`, so a comment containing either word corrupts the port scan
   and produces a misleading error

Two further eSim behaviours worth knowing, documented in the project README:
eSim reads the **legacy Spice-format** netlist export, not KiCad 6's
S-expression format (choosing the obvious "KiCad" tab produces a file it
silently cannot parse); and its Analysis tab double-applies the unit suffix if
you enter scientific notation.

---

## Toolchain

| Tool | Version |
|---|---|
| eSim | 2.5 |
| ngspice | 35 (NGHDL-patched) |
| GHDL | 4.1.0 LLVM |
| GTKWave | 3.3.104 |
| KiCad | 6.0 |
| Ubuntu | 22.04.5 LTS |

---

## Reproducing results

**VHDL modules** — fast loop, no eSim required:

```bash
cd vhdl
./scripts/run.sh bit_timing  400us
./scripts/run.sh bit_stuff   200us
./scripts/run.sh crc15       15ms     # generate vectors first
./scripts/run.sh frame_gen   20ms
./scripts/run.sh frame_rx    30ms
./scripts/run.sh error_mgmt  10ms
./scripts/run.sh error_gen   10ms
```

Integration harnesses have no matching `src` module, so run GHDL directly:

```bash
ghdl -i src/*.vhdl tb/tb_node.vhdl && ghdl -m tb_node
ghdl -r tb_node --stop-time=40ms
```

**Reference vectors:**

```bash
cd vhdl && python3 ../tools/crc15_ref.py && python3 ../tools/frame_ref.py
```

**Analog PHY:**

```bash
cd spice && ./run_phy_regression.sh      # 18 checks
```

**Mixed-signal** (requires the NGHDL model built from `nghdl_model/`):

```bash
cd spice
ngspice -b can_mixed.cir          # two nodes
ngspice -b can_4node.cir          # four-node arbitration
ngspice -b can_busoff_perm.cir    # fault confinement to bus-off
```

**eSim project:** open `esim_project/` in eSim, then KiCad-to-Ngspice →
Convert → Simulate. See its `README.txt` for the exact steps, including the
netlist-format caveat.

---

## Verification approach

Three levels, each catching a different class of defect:

| Level | Method | Catches |
|---|---|---|
| Unit | Self-checking GHDL testbench per module | Logic errors, boundary conditions |
| Integration | Multi-module GHDL testbenches | Interface and handshake errors |
| System | Mixed-signal eSim/ngspice simulations | Analog–digital interaction, real bus behaviour |

Two principles were applied throughout:

**Reference models are written from the standard, not from the RTL.** If the
reference is derived from the code, both share any misunderstanding and agree
while both being wrong.

**Every mechanism has a discriminating test** — one that fails if the mechanism
were hardwired to succeed. Remove the receiver and require `ack_err`; remove
the lowest-ID node and require the next one to win; check an error-passive node
drives *zero* dominant bits.

Predicted and measured values for every test are in `docs/measurements.md`.

---

## Known limitations

Stated explicitly rather than omitted. Full list in `docs/verification.md`:

- Standard 11-bit identifiers only; no extended identifiers, no overload frames
- A node that loses arbitration abandons the frame rather than retrying
- All nodes share a clock, so resynchronisation is implemented and unit-tested
  but not exercised against genuinely skewed oscillators
- The comparator has no common-mode input range, so the model is optimistic
  outside the range where real transceivers saturate
- The simulated transceiver is 21.6 ns where real parts are 100–255 ns; all
  length derivations use the conservative 150 ns figure

---

## License

Educational project submitted to FOSSEE, IIT Bombay.
