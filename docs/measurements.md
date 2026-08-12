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
