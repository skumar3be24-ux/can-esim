# CAN Protocol — Verification Matrix

Every test in the project, what it proves, and the measured result.

**Method.** Wherever possible, results are checked against an **independently
written reference model** rather than against hand-computed expectations. The
Python references in `tools/` are written from ISO 11898-1, deliberately not
derived from the VHDL, so the two can genuinely disagree. Predictions are
recorded before measurement; errors are quoted.

**Status key:** ✅ verified · ⚠️ verified with stated limitation · ❌ not covered

---

## Phase 2 — Analog physical layer

Netlists in `spice/`. Regression: `spice/run_phy_regression.sh` re-runs all
18 checks against the frozen values in `docs/phy_spec.md`.

| # | Test | Predicted | Measured | Error | Status |
|---|---|---|---|---|---|
| P1 | DC dominant V_diff | 2.000 V | 1.996406 V | −0.18% | ✅ |
| P2 | DC recessive V_diff | 0 V | 2.99e-07 V | — | ✅ |
| P3 | TX→RX loop delay | ~35 ns | 35 ns | — | ✅ |
| P4 | Edge rise/fall | 20 ns | 20 ns | — | ✅ |
| P5 | Wired-AND, all 4 driver states | dominant wins | exact | — | ✅ |
| P6 | Propagation delay, 220 m | 1.100 µs | 1.113567 µs | +1.2% | ✅ |
| P7 | TX → far-end RX | ~1.135 µs | 1.135200 µs | — | ✅ |
| P8 | Γ, open circuit | +1.000 | +1.000 | <0.01% | ✅ |
| P9 | Γ, 1 kΩ | +0.786 | +0.786 | 0.03% | ✅ |
| P10 | Γ, 120 Ω matched | 0.000 | 0.000 | — | ✅ |
| P11 | Γ, 60 Ω | −0.333 | −0.333 | 0.01% | ✅ |
| P12 | DC common-mode rejection | exact | exact to 7 digits | 0 | ✅ |
| P13 | CMRR, 1% R / 5% C | 30–50 dB | 33.3 dB | — | ✅ |
| P14 | 1 Mbit/s over 220 m | must fail | failed (1.5e-07 V) | — | ✅ |
| P15 | 500 kbit/s one-way | passes | passes | — | ✅ |
| P16 | Sample point vs reflections | dominant at 70% margin | confirmed | — | ✅ |

**Key derivations established, not assumed:**

- `PROP_SEG = 5 tq` — from measured round trip 2.270 µs vs 2.500 µs allowance (9.2% margin)
- Sample point at 75% — placed **more than one round trip** after the edge
- Two independent length constraints — one-way (reception) and round-trip (arbitration)

**Stated model limitations:** tanh comparator has no common-mode input range
(real parts saturate at ±12 V); simulated transceiver is 21.6 ns against
100–255 ns real, so all length derivations use the conservative 150 ns figure;
transmission line is lossless; component tolerances modelled in one test only;
no EMI or bus faults in the PHY characterisation.

---

## Phase 3 — Digital controller, transmit side

| # | Module | Test | Result | Status |
|---|---|---|---|---|
| D1 | `bit_timing` | Free-running bit period | 16 tq | ✅ |
| D2 | `bit_timing` | Sample point position | tq 12 (75.00%) | ✅ |
| D3 | `bit_timing` | Hard sync mid-bit | tq_index → 0 | ✅ |
| D4 | `bit_timing` | Resync, e = +3 | 19 tq bit | ✅ |
| D5 | `bit_timing` | Resync, e = −2 | 15 tq (truncate-to-edge) | ✅ |
| D6 | `bit_timing` | SJW cap, e = +9 | 20 tq, not 25 | ✅ |
| D7 | `bit_stuff` | No stuffing below 5 | 0 stuff bits | ✅ |
| D8 | `bit_stuff` | One stuff bit at 5 | 1, opposite polarity | ✅ |
| D9 | `bit_stuff` | Destuffer removes stuff bit | 6 payload from 7 | ✅ |
| D10 | `bit_stuff` | Six identical bits | `stuff_err` raised | ✅ |
| D11 | `bit_stuff` | Stuffing disabled | 0 stuff bits | ✅ |
| D12 | `bit_stuff` | **Round trip, 5 patterns** | all recover exactly | ✅ |
| D13 | `crc15` | **417 vectors vs Python reference** | **417/417 match** | ✅ |
| D14 | `frame_gen` | **68 frames bit-exact** | **68/68, zero stuff_en errors** | ✅ |
| D15 | `can_tx_path` | 6 frames on the bus at 125 kbit/s | 6/6 bit-exact | ✅ |

**D12 is decisive for stuffing:** twelve identical bits produce **two** stuff
bits, proving the run counter resets on a stuffed bit. Isolated tests cannot
reach this.

**D13 is the strongest single result:** the reference was written from the ISO
definition, not from the RTL, and covers 400 random frames plus targeted edge
cases (all-zero, single-bit MSB/LSB, all-ones, alternating, register-width).

---

## Phase 4 — Receive, ACK, arbitration

| # | Test | Result | Status |
|---|---|---|---|
| R1 | `frame_rx` decode, 20 frames | ID/DLC/data correct, CRC matched | ✅ |
| R2 | Injected CRC error (flipped ID bit) | `crc_err`, frame rejected | ✅ |
| R3 | Injected form error (dominant EOF) | `form_err`, frame rejected | ✅ |
| R4 | Injected stuff error (6 identical) | `stuff_err` | ✅ |
| R5 | ACK — receiver present | `ack_ok`, bus dominant in slot | ✅ |
| R6 | **ACK — receiver absent** | **`ack_err`** | ✅ |
| R7 | Arbitration, A alone | nobody loses | ✅ |
| R8 | Arbitration, A vs B | B loses at id(8) | ✅ |
| R9 | Arbitration, A vs B vs C | C then B lose | ✅ |
| R10 | **Arbitration, B vs C (no A)** | **C loses, B wins** | ✅ |
| R11 | Two-node: node 0 → node 1 | received + acknowledged | ✅ |
| R12 | Two-node: node 1 → node 0 | received + acknowledged | ✅ |
| R13 | Two-node collision | loser received winner's frame intact | ✅ |
| R14 | **No self-ACK** | node did not acknowledge itself | ✅ |

**R6, R10 and R14 are the discriminating tests.** R5 alone would pass with an
ACK check hardwired to succeed; R7–R9 would pass if node A never lost by
construction; R11–R13 would pass if a node acknowledged itself.

---

## Phase 5 — Error handling and fault confinement

| # | Test | Result | Status |
|---|---|---|---|
| E1 | TEC/REC reset state | 0, 0, error-active | ✅ |
| E2 | Transmit error | TEC +8 | ✅ |
| E3 | Success | TEC −1 (8 successes undo 1 error) | ✅ |
| E4 | No counter underflow | stays 0 | ✅ |
| E5 | Receive error / success | REC +1 / −1 | ✅ |
| E6 | Big receive error | REC +8 | ⚠️ |
| E7 | **Error-passive boundary** | TEC=120 active, **TEC=128 passive** | ✅ |
| E8 | **Bus-off boundary** | TEC=248 passive, **TEC=256 bus-off** | ✅ |
| E9 | Bus-off absorbing | further errors change nothing | ✅ |
| E10 | Recovery | 127 idles still off, **128th recovers** | ✅ |
| E11 | Error-active flag | 6 dominant bits | ✅ |
| E12 | Error delimiter | 8 recessive bits | ✅ |
| E13 | **Error-passive flag** | **0 dominant bits driven** | ✅ |
| E14 | Superposition | delimiter waits for recessive bus | ✅ |
| E15 | Stuck dominant bus | bounded wait, reported | ✅ |
| E16 | Clean frame, integrated | no spurious errors, counters 0 | ✅ |
| E17 | Corrupted frame, integrated | rejected, error frame, REC +3 | ✅ |
| E18 | Transmit bit monitoring | TEC 0 → 28 on the transmitter | ✅ |

**E6 limitation:** `rx_err_big` is tied to `'0'` in the integrated node. The
standard uses it when a receiver detects a bit error while sending its own
*active* error flag, which requires monitoring during the error frame — and the
current design deliberately suppresses detection there to stop a cascade.
Verified in isolation, unreachable in integration.

---

## Mixed-signal — VHDL controllers on the analog PHY

Netlists in `spice/`. NGHDL models built from `nghdl_model/`.

| # | Test | Result | Status |
|---|---|---|---|
| M1 | Two nodes, clock/reset reaching models | 5.0 / 0.0 V | ✅ |
| M2 | Two-node arbitration | node 0 won, node 1 detected loss at 57 µs | ✅ |
| M3 | ACK across the analog boundary | acknowledged at 385 µs | ✅ |
| M4 | Reception across the boundary | received at 455 µs | ✅ |
| M5 | **Error frames on clean traffic** | **0 — no false positives** | ✅ |
| M6 | **Four-node arbitration** | A won; D, C, B lost | ✅ |
| M7 | **Four-node loss ordering** | **40.5 / 48.5 / 57.0 µs — one bit time apart** | ✅ |
| M8 | Non-destructive arbitration | all 3 losers received the winner's frame | ✅ |
| M9 | Intermittent fault (30% duty) | node survives — correct | ✅ |
| M10 | **Permanent fault → bus-off** | **bus-off at 5.626 ms** | ✅ |
| M11 | **Fault confinement** | **healthy node unaffected in every run** | ✅ |
| M12 | Bus-off suppression | `tx_busy` → 0 after bus-off | ✅ |

**M7 is the strongest arbitration evidence in the project.** The loss order was
derived from the identifier bit patterns *before* measurement, and the losses
land exactly one bit time (8 µs) apart, matching D at id(10), C at id(9), B at
id(8).

**M9 vs M10 together** show fault confinement behaving correctly in both
directions: a node survives a recoverable 30%-duty fault (TEC reaches equilibrium
below 256 because successes decrement it) and removes itself only for a
persistent one.

---

## Not covered

Stated explicitly rather than omitted:

| Area | Status |
|---|---|
| Extended (29-bit) identifiers | ❌ standard format only |
| Overload frames | ❌ |
| Automatic retransmission after arbitration loss | ❌ node abandons the frame |
| `rx_err_big` (+8 receive) in integration | ❌ see E6 |
| Bit errors during CRC/ACK delimiter | ⚠️ suppressed to avoid false positives |
| Independent oscillators between nodes | ❌ all nodes share a clock |
| REC 119–127 band on reception above 127 | ⚠️ implemented as 127, untested |
| Transceiver common-mode input range | ❌ model has none; real parts saturate |
| Bus faults: open, short to VCC/GND, single-wire | ❌ only the differential short |

The oscillator-independence gap is the most significant: real nodes resynchronise
using the Day 22 logic, which is implemented and unit-tested but never exercised
against genuinely skewed clocks.

---

## Reproducing

```bash
# Analog PHY regression (18 checks)
cd spice && ./run_phy_regression.sh

# Digital modules
cd vhdl && ./scripts/run.sh bit_timing 400us
./scripts/run.sh bit_stuff  200us
./scripts/run.sh crc15      15ms     # regenerate vectors first
./scripts/run.sh frame_gen  20ms
./scripts/run.sh frame_rx   30ms
./scripts/run.sh error_mgmt 10ms
./scripts/run.sh error_gen  10ms

# Integration harnesses (no matching src module, so run GHDL directly)
ghdl -i src/*.vhdl tb/tb_node.vhdl && ghdl -m tb_node
ghdl -r tb_node --stop-time=40ms

# Reference vectors
cd vhdl && python3 ../tools/crc15_ref.py && python3 ../tools/frame_ref.py

# Mixed-signal (requires the NGHDL model built from nghdl_model/)
cd spice && ngspice -b can_mixed.cir
ngspice -b can_4node.cir
ngspice -b can_busoff_perm.cir
```
