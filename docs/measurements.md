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
