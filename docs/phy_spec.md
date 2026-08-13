# CAN Physical Layer — Frozen Specification

**Status: FROZEN as of Day 21.** No parameter in this document changes for the
remainder of the project. The VHDL controller is written against these values.
Any future change requires re-running the full PHY regression (`spice/run_phy_regression.sh`)
and re-freezing.

Derived and verified across Days 13–20. Every number below is either a design
choice with stated justification, or a measurement with its predicted value and
error.

---

## 1. Frozen parameters

### 1.1 Bit timing

| Parameter | Value | Source |
|---|---|---|
| Bit rate | 125 kbit/s | design choice |
| Nominal bit time | 8.000 µs | 1 / 125 k |
| Time quanta per bit | 16 | design choice |
| Time quantum (tq) | 500 ns | 8.000 µs / 16 |
| VHDL clock frequency | 2.000 MHz | 1 / tq |
| SYNC_SEG | 1 tq = 0.500 µs | ISO 11898-1 fixed |
| PROP_SEG | 5 tq = 2.500 µs | **measured, Day 17** |
| PHASE_SEG1 | 6 tq = 3.000 µs | design choice |
| PHASE_SEG2 | 4 tq = 2.000 µs | design choice |
| Sample point | 12 tq = 6.000 µs = 75.00% | **justified, Day 18** |
| SJW | 4 tq = 2.000 µs | = PHASE_SEG2 |
| Oscillator tolerance | 0.98% | derived from SJW |

### 1.2 Electrical

| Parameter | Value | Source |
|---|---|---|
| VCC | 5.0 V | design choice |
| Dominant CANH / CANL | 3.5 V / 1.5 V | ISO 11898-2 nominal |
| Dominant V_diff | 2.0 V (meas 1.996406 V) | Day 13 |
| Recessive CANH / CANL | 2.5 V / 2.5 V | biased |
| Recessive V_diff | 0 V (meas 2.9910e-07 V) | Day 13 |
| Termination | 120 Ω × 2 → 60 Ω differential | ISO 11898-2 |
| Driver on-resistance R_on | **45.0 Ω** | 1.5 V / 33.333 mA |
| Bias network | 10 kΩ × 2 to 2.5 V | design choice |
| Leak resistors | 100 MΩ | Day 13 fix (1 MΩ caused 2.4752 V error) |
| Bus capacitance | 1 nF per line, C_diff 500 pF | design choice |
| Receiver threshold dominant | V_diff > 0.9 V | ISO 11898-2 |
| Receiver threshold recessive | V_diff < 0.5 V | ISO 11898-2 |

### 1.3 Bus / cable

| Parameter | Value | Source |
|---|---|---|
| Max bus length | 220 m | derived from PROP_SEG |
| Characteristic impedance Z₀ | 120 Ω | ISO 11898-2 |
| Propagation velocity | 2 × 10⁸ m/s | 2/3 c, typical twisted pair |
| Line delay for 220 m | 1.100 µs (meas 1.113567 µs) | Day 17 |
| Transceiver loop delay (modelled) | 21.6 ns | Day 17 |
| Transceiver loop delay (design allowance) | **150 ns** | real-silicon figure |

### 1.4 Protocol constants

| Parameter | Value |
|---|---|
| CRC-15 polynomial | 0x4599 |
| Node A ID | 0x0A5 (wins arbitration) |
| Node B ID | 0x123 (loses at ID bit 8) |
| Node C ID | 0x2AA (loses at ID bit 9) |
| Node D | extended 0x297ABCD, base 0x0A5 (loses at SRR) |

---

## 2. Canonical models

### 2.1 Driver

```spice
.model swmod SW(Vt=2.5 Vh=0.2 Ron=45 Roff=1e9)
Bdrv ctrl 0 V = 5 - V(tx_ctl)      ; dominant (tx=0) must CLOSE the switches
Sh vcc  canh ctrl 0 swmod
Sl canl 0    ctrl 0 swmod
```

The inverting `Bdrv` is essential: CAN dominant is logic 0, but the switch model
closes on a *high* control voltage.

### 2.2 Receiver

```spice
Bcomp rx_ana 0 V = 2.5*(1 - tanh(10*(V(canh)-V(canl)-0.7)))
```

Centred at 0.7 V, midway between the 0.5 V recessive and 0.9 V dominant
thresholds. Gain 10 gives a transition width of roughly ±0.2 V.

### 2.3 Digital interface

```spice
.model adcmod adc_bridge(in_low=1.5 in_high=3.5)
.model dacmod dac_bridge(out_low=0 out_high=5 out_undef=2.5
+                        t_rise=20n t_fall=20n)
```

### 2.4 Transmission line

```spice
Tline canh_a canl_a canh_b canl_b Z0=120 TD=1.1u
```

---

## 3. Verified results summary

| Day | What was verified | Predicted | Measured | Error |
|---|---|---|---|---|
| 13 | DC dominant V_diff | 2.000 V | 1.996406 V | −0.18% |
| 13 | DC recessive V_diff | 0 V | 2.9910e-07 V | — |
| 14 | Loopback TX→RX delay | ~35 ns | 35 ns | — |
| 15 | Edge rise/fall | 20 ns | matched | — |
| 16 | Wired-AND (all 4 states) | dominant wins | exact | — |
| 17 | Propagation delay 220 m | 1.100 µs | 1.113567 µs | +1.2% |
| 17 | TX → far-end RX | ~1.135 µs | 1.135200 µs | — |
| 18 | Γ open | +1.000 | +1.000 | <0.01% |
| 18 | Γ 1 kΩ | +0.786 | +0.786 | 0.03% |
| 18 | Γ 60 Ω | −0.333 | −0.333 | 0.01% |
| 19 | DC common-mode rejection | exact | exact (7 digits) | 0 |
| 19 | CMRR, 1% R / 5% C | 30–50 dB | 33.3 dB | — |
| 20 | 1 Mbit/s over 220 m | fails | fails (1.5e-07 V) | — |

---

## 4. Key derivations

### 4.1 Why PROP_SEG = 5 tq (Day 17)

```
one-way cable delay (measured)  t_bus = 1.1136 µs
transceiver loop delay (measured) t_trx = 0.0216 µs
round trip = 2 × (1.1136 + 0.0216)     = 2.2704 µs
PROP_SEG   = 5 tq                      = 2.500 µs
margin     = 0.230 µs = 0.46 tq = 9.2%
```

Small margin by design — 220 m was *derived* as the maximum for this allocation.

### 4.2 Why the sample point is at 75% (Day 18)

```
reflection settling time = 1 round trip = 2.27 µs
sample instant = 12 tq                  = 6.000 µs
6.000 > 2.27  →  all reflections decayed before sampling
```

The sample point is placed to be **more than one round trip after the edge**.
Verified: with the far end fully open (Γ = +1), the receiver still read dominant
with 70% margin.

### 4.3 Two independent length constraints (Day 20)

```
one-way   (reception)   : t_cable < sample instant
round-trip(arbitration) : 2 × (t_cable + t_trx) < PROP_SEG
```

| Rate | One-way | Round trip | Result |
|---|---|---|---|
| 125 k | 1.114 < 6.000 ✓ | 2.271 < 2.500 ✓ | works |
| 500 k | 1.114 < 1.500 ✓ | 2.271 > 0.625 ✗ | arbitration fails |
| 1 M | 1.114 > 0.750 ✗ | 2.271 > 0.3125 ✗ | both fail |

500 kbit/s over 220 m would receive data correctly and fail arbitration
completely. Testing reception alone gives a false pass.

---

## 5. Model limitations — stated explicitly

These are known gaps between this model and real silicon. Each is a place where
the simulation is **optimistic**.

**5.1 The comparator has no common-mode input range.** Real CAN transceivers
saturate outside roughly −12 V to +12 V and rejection collapses. The `tanh`
model rejects arbitrary offsets. At ±12 V ground offset the modelled input pins
reach +15.44 V and −10.44 V, where real silicon would have failed. Consequence:
the ISO 11898-2 requirement of −2 V to +7 V exists because of the *transceiver
input range*, not because differential signalling degrades. Within ±7 V the model
is trustworthy.

**5.2 The transceiver is too fast.** Modelled loop delay is 21.6 ns; real parts
are 100–255 ns. All length derivations use the conservative 150 ns figure rather
than the modelled value, so the 220 m limit is honest — but any simulation
result involving transceiver timing is optimistic.

**5.3 The transmission line is ideal.** The `T` element is lossless and
dispersionless. Real twisted pair has skin-effect and dielectric loss that
increase with frequency and distance. Measured far-end level was 0.26% below
near-end, which is the termination divider, not cable loss.

**5.4 Component tolerances are only modelled in one test.** Day 19 Part 3 used
1% resistors and 5% capacitors. Everything else assumes exact values.

**5.5 No EMI, no bus faults.** Open circuit, short to ground, short to VCC, and
single-wire operation are not modelled. Real CAN transceivers have specified
degraded-mode behaviour for these.

---

## 6. Files

| File | Purpose |
|---|---|
| `spice/phy_dc.cir` | DC operating points, both bus states |
| `spice/phy_loopback.cir` | TX → RX loop delay |
| `spice/phy_edges.cir` | Rise/fall edge characterisation |
| `spice/phy_wired_and.cir` | Wired-AND, all four driver combinations |
| `spice/phy_tline.cir` | 220 m transmission line, propagation delay |
| `spice/phy_reflection.cir` | Termination mismatch, reflection coefficients |
| `spice/phy_cmrr.cir` | Common-mode rejection **(rev A — DC test is WRONG, kept as documentation)** |
| `spice/phy_cmrr2.cir` | Common-mode rejection, corrected |
| `spice/phy_bitrate.cir` | Multi-bit-rate validation |
| `spice/run_phy_regression.sh` | Re-runs everything above |

---

## 7. Interface contract for the VHDL controller

The controller is written against exactly this:

- **Clock:** 2.000 MHz, one tq per clock cycle.
- **Bit time:** 16 clock cycles.
- **Sample point:** clock cycle 12 of each bit (0-indexed from SYNC_SEG).
- **`can_tx` output:** `'0'` = dominant, `'1'` = recessive. Drives the analog
  driver through a `dac_bridge`.
- **`can_rx` input:** `'0'` = dominant, `'1'` = recessive. Arrives from the
  analog comparator through an `adc_bridge`.
- **Loop delay TX → own RX:** 35 ns ≈ 0.07 tq. Negligible; the controller may
  read back its own transmitted bit within the same tq.
- **Bus is wired-AND:** any node driving dominant forces the whole bus dominant.
  Verified exhaustively, Day 16.
