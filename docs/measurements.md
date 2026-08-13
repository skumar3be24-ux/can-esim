# Measurements: predicted vs measured

| Test | Predicted | Measured | Error |
|---|---|---|---|
| RC 1-tau (1-e^-1) | 0.6321206 | 0.6321209 | 0.00005% |
| XSPICE dac high | 5.000 V | 5.000000 V | 0% |
| XSPICE dac low | 0.000 V | 0.000000 V | 0% |

## Day 13 - PHY DC levels (spice/phy_dc.cir)

| Quantity | Predicted | Measured | Error |
|---|---|---|---|
| Dominant CANH | 3.500 V | 3.498073 V | -0.055% |
| Dominant CANL | 1.500 V | 1.501703 V | +0.11% |
| Dominant Vdiff | 2.000 V | 1.996371 V | -0.18% |
| Driver current | 33.333 mA | 33.376 mA | +0.13% |
| Driver power | 166.7 mW | 166.88 mW | +0.11% |
| Recessive CANH/CANL | 2.500 V | 2.499750 V | -0.010% |
| Recessive Vdiff | 0.000 V | 1.5e-7 V | - |

R_on = 45 ohm confirmed by measurement. Residual ~2 mV dominant offset is the
10k bias network loading the driver (predicted 0.3% in roadmap 3.8.4).
Rleak raised 1M -> 100M: at 1M the recessive level sat at 2.4752 V, a divider
artefact (2.5 x 1M/1.01M), not physics. Matters for Day 75 noise margins.

## Day 14 - PHY digital loopback (spice/phy_loopback.cir)

| Quantity | Predicted | Measured |
|---|---|---|
| Dominant CANH | 3.498 V | 3.498202 V |
| Dominant CANL | 1.502 V | 1.501796 V |
| Recessive CANH = CANL | 2.4998 V | 2.499955 V |
| TX / RX at dominant | 0 / 0 | 0 / 0 |
| TX / RX at recessive | 5 / 5 | 5 / 5 |
| TX->RX loop delay | << 500 ns | 35.4 ns |
| Bit period | 8.000 us | 8.000000 us |

Loop delay is 35.4 ns against the 150 ns transceiver allowance used to size
PROP_SEG, so the 220 m maximum bus length in roadmap 3.4 holds with margin.
Driver control is inverted from TX (Bdrv: ctrl = 5 - tx_ctl) because dominant
is logic 0 but requires the switches closed - real CAN transceivers are
active-low on TXD for the same reason.

## Day 15 - Edge rate vs bus capacitance (spice/phy_edges.cir)

t_r = ln(9) x R_src x C_diff, R_src = (45+45) || 60 = 36.00 ohm, C_diff = C/2

| C per line | C_diff | Predicted t_r | Measured t_r | Error |
|---|---|---|---|---|
| 100 pF | 50 pF | 3.96 ns | 3.934 ns | -0.66% |
| 500 pF | 250 pF | 19.8 ns | 19.870 ns | +0.35% |
| 1 nF | 500 pF | 39.6 ns | 39.761 ns | +0.41% |
| 5 nF | 2.5 nF | 198 ns | 198.844 ns | +0.43% |
| 10 nF | 5 nF | 396 ns | 397.687 ns | +0.43% |

Linear across two decades: 100x capacitance gives 101x rise time.
Systematic +0.4% offset is the 2.2 approximation; exact factor is ln(9)=2.19722,
giving 39.55 ns at 1 nF versus 39.761 ns measured, remainder from the 20 ns
bridge transition.

PRACTICAL BUS LOADING LIMIT: at 10 nF the edge is 397 ns = 79% of one time
quantum (500 ns), so the bus is still settling at the sample point. Each
additional transceiver adds input capacitance, which is what bounds node count.

## Day 16 - WIRED-AND TRUTH TABLE (spice/phy_wired_and.cir) [evidence A8]

Three independent drivers on one CANH/CANL pair. No logic in the netlist
computes AND; the bus does it, because recessive is passive and dominant
is actively driven.

| t (us) | TX_A | TX_B | TX_C | Vdiff | RX | Bus |
|---|---|---|---|---|---|---|
| 5 | 1 | 1 | 1 | 0.0000004 V | 1 | recessive |
| 15 | 1 | 1 | 0 | 1.9964 V | 0 | dominant |
| 25 | 1 | 0 | 1 | 1.9964 V | 0 | dominant |
| 35 | 1 | 0 | 0 | 2.8535 V | 0 | dominant |
| 45 | 0 | 1 | 1 | 1.9964 V | 0 | dominant |
| 55 | 0 | 1 | 0 | 2.8535 V | 0 | dominant |
| 65 | 0 | 0 | 1 | 2.8535 V | 0 | dominant |
| 75 | 0 | 0 | 0 | 3.3300 V | 0 | dominant |

Recessive in exactly one row: bus = TX_A AND TX_B AND TX_C. CONFIRMED.

Multi-driver levels (R_on_eff = 45/n):

| n | Predicted Vdiff | Measured | Error | CANH pred/meas | CANL pred/meas |
|---|---|---|---|---|---|
| 0 | 0.000 V | 4.5e-7 V | - | 2.500 / 2.4998 | 2.500 / 2.4998 |
| 1 | 2.000 V | 1.9964 V | -0.18% | 3.500 / 3.4982 | 1.500 / 1.5018 |
| 2 | 2.857 V | 2.8535 V | -0.12% | 3.929 / 3.9267 | 1.071 / 1.0733 |
| 3 | 3.333 V | 3.3300 V | -0.09% | 4.167 / 4.1650 | 0.833 / 0.8350 |

Vdiff RISES with the number of dominant drivers because on-resistances
parallel. A logic gate cannot do this - it is the signature of real parallel
current sources on a shared 60 ohm load. In the Day 66 arbitration waveform
this appears as Vdiff stepping 3.33 -> 2.86 -> 2.00 V as nodes drop out.

## Day 17 - Transmission line, 220 m bus (spice/phy_tline.cir)

Line: Z0 = 120 ohm, v = 2e8 m/s, L = 600 nH/m, C = 41.67 pF/m
For 220 m: L = 132 uH, C = 9.167 nF, TD = 1.100 us

| Measurement | Predicted | Measured | Error |
|---|---|---|---|
| Propagation delay | 1.100 us | 1.113567 us | +1.2% |
| TX -> far RX | ~1.135 us | 1.135200 us | - |
| Near-end Vdiff dominant | 1.996 V | 1.996406 V | - |
| Far-end Vdiff dominant | 1.996 V | 1.991271 V | -0.26% |
| Both ends recessive | 0 V | 3.0e-7 V | - |
| Far-end RX dom / rec | 0 / 5 V | 0 / 5 V | exact |

The +1.2% on t_prop is the 50% crossing of a finite-rise edge; line delay is
1.100 us by construction. t_txrx - t_prop = 21.6 ns = transceiver contribution.
No reflections: both ends terminated 120 ohm into a 120 ohm line, Gamma = 0.
Far-end level 0.26% low is real line loss, not ringing.

PROP_SEG JUSTIFICATION (this is why PROP_SEG = 5 tq):
  t_bus (measured)   = 1.1136 us
  t_trx (measured)   = 0.0216 us
  round trip         = 2 x (1.1136 + 0.0216) = 2.2704 us
  PROP_SEG = 5 tq    = 2.500 us
  margin             = 0.230 us = 0.46 tq = 9.2%

Margin is small BY DESIGN - 220 m was derived as the maximum length for this
segment allocation. Day 71 should see arbitration fail around 240-250 m.

HONESTY NOTE for report: the design allowed 150 ns for the transceiver but the
simulated one is 21.6 ns. Real CAN transceivers are 100-255 ns, so 150 ns is the
figure to quote; the simulation is optimistic about the transceiver, not
conservative.

## Day 18 - Termination mismatch and reflections (spice/phy_reflection.cir)

Gamma = (R_L - Z0)/(R_L + Z0), Z0 = 120 ohm. Far end mis-terminated, near
end held at 120 ohm. Driver actual output is 1.9964 V, not nominal 2.000 V.

| R_L | Gamma | Peak pred = 1.9964*(1+G) | Peak meas | Error |
|---|---|---|---|---|
| 120 ohm | 0.000 | 1.996 V | 1.996406 V | -0.00% |
| open | +1.000 | 3.993 V | 3.992809 V | -0.00% |
| 1 kohm | +0.786 | 3.566 V | 3.565009 V | -0.03% |
| 60 ohm | -0.333 | 1.331 V | 1.330937 V | -0.01% |

Using the MEASURED driver output rather than the nominal 2.000 V reproduces
all four peaks to four significant figures. Gamma confirmed to <0.25%.

SETTLED LEVELS at t = 16 us (T element is a DC short, so far end sees
120 || R_L driven through 2 x 45 ohm):

| R_L | R_par | Divider pred | Measured | Note |
|---|---|---|---|---|
| 120 | 60.0 | 2.000 V | 1.996 V | matches |
| open | 120.0 | 2.857 V | 3.034 V | +6%, bias network ignored |
| 1 k | 107.1 | 2.719 V | 2.796 V | +3%, bias network ignored |
| 60 | 40.0 | 1.538 V | 1.533 V | matches |

The two high-impedance cases run above the simple divider because the 10 k
bias resistors and 100 Mohm leaks pull toward 2.5 V; their effect grows as
the load impedance rises. Where the load dominates, the divider matches to
0.3%.

KEY RESULT - rx_samp = 0.000 V (dominant) in ALL FOUR cases, including a
fully open far end. Worst settled level 1.533 V against a 0.9 V dominant
threshold: 70% margin.

WHY THE SAMPLE POINT IS AT 75%:
  reflection settling time = 1 round trip = 2.27 us
  sample instant           = 12 tq = 6.000 us into the bit
  6.000 us > 2.27 us, so all reflections have decayed before sampling.
The sample point is placed to be MORE THAN ONE ROUND TRIP after the edge.
That is the design rule; this experiment demonstrates it.

CAVEAT: this tested a static dominant bit. Mis-termination is worst during
arbitration when the bus flips every bit. At 125 kbit/s the 8 us bit far
exceeds the 2.27 us round trip so there is no inter-bit overlap. At 1 Mbit/s
the 1 us bit is SHORTER than the round trip - which is why 1 Mbit/s CAN is
limited to about 40 m. Day 20 should demonstrate this.

## Day 19 - Common-mode rejection (spice/phy_cmrr.cir, spice/phy_cmrr2.cir)

### REV A WAS WRONG - recorded because the failure is instructive
phy_cmrr.cir applied the ground offset only to the 10 k bias network while the
45 ohm driver stayed referenced to global ground. The driver clamped the bus and
the offset was attenuated 10000/45 = 222:1. Measured span was 0.108 V for a 24 V
sweep = 222:1 exactly, which confirms the mechanism. The test was measuring
driver impedance ratio, not common-mode rejection.

FIX (phy_cmrr2.cir): node B termination, bias, capacitance, leak paths and
comparator ALL reference gnd_b. Nothing at node B touches global ground.

### CORRECTED DC GROUND OFFSET SWEEP

| Offset | vcmb (node B CM) | vdb | vda | vhb | vlb | RX | Real xcvr |
|---|---|---|---|---|---|---|---|
| -12 V | +14.446 V | 1.992825 | 1.992825 | +15.443 | +13.450 | dom | FAILS |
| -7 V | +9.469 V | 1.992825 | 1.992825 | +10.465 | +8.472 | dom | ok |
| -2 V | +4.491 V | 1.992825 | 1.992825 | +5.487 | +3.495 | dom | ok |
| 0 V | +2.500 V | 1.992825 | 1.992825 | +3.496 | +1.504 | dom | ok |
| +2 V | +0.509 V | 1.992825 | 1.992825 | +1.505 | -0.487 | dom | ok |
| +7 V | -4.469 V | 1.992825 | 1.992825 | -3.472 | -5.465 | dom | ok |
| +12 V | -9.446 V | 1.992825 | 1.992825 | -8.450 | -10.443 | dom | FAILS |

vcmb spans 23.89 V for a 24 V sweep (tracks -VGND to 0.5%) while vdb is
IDENTICAL TO SEVEN DIGITS at every offset. Rejection is EXACT, not approximate:
  (canh - gnd_b) - (canl - gnd_b) = canh - canl
the offset cancels algebraically. vda = vdb throughout, so both nodes agree on
the differential while disagreeing by 24 V on absolute potential.

Note vdb = 1.992825 V here vs 1.996406 V on earlier days (-0.18%). This netlist
has TWO 10 k bias networks (node A and node B) loading the driver instead of
one. Expected, and it confirms the two-node model is genuinely two nodes.

### CMRR - AC common-mode transient (from rev A, this part was sound)
1 V step injected onto both wires through equal 100 pF at t = 14 us.

| Case | Vdiff before | Vdiff peak | Vdiff min | Worst excursion |
|---|---|---|---|---|
| matched components | 1.996406 | 1.996406 | 1.996406 | 0 (exactly) |
| 1% R, 5% C tolerance | 1.996406 | 1.997650 | 1.994766 | 1.640 mV |

The matched case rejects perfectly to seven digits - not a result, just
confirmation that zero mismatch gives zero leakage. Only the mismatched case
is quotable.

  CMRR referred to the 1 V source   = 20*log10(1.000/0.001640) = 55.7 dB
  CMRR referred to CM that appeared = 20*log10(0.076/0.001640) = 33.3 dB

The 100 pF coupling only moved the actual common mode by 76 mV, so 33.3 dB is
the honest figure and it sits in the real-transceiver range of 30-50 dB.
Error is 1.640 mV against a 0.9 V threshold: 550x margin. RX never wavered.

### MODEL LIMITATION - state this in the report
The tanh comparator has NO common-mode input range. Real CAN transceivers
saturate outside roughly -12..+12 V and rejection collapses entirely. At +/-12 V
offset our node B pins reach +15.44 V and -10.44 V, where real silicon would
have failed - but this model reports success.

CONSEQUENCE: the ISO 11898-2 requirement of -2 V to +7 V exists because of the
TRANSCEIVER INPUT RANGE, not because differential signalling degrades. Within
-7..+7 V our node B pins stay inside +/-12 V and the model is trustworthy.
Outside that, it is optimistic.
