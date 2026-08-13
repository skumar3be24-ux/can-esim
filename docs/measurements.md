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

## Day 20 - Multi-bit-rate validation (spice/phy_bitrate.cir)

Tests the Day 18 prediction that high-rate CAN is length-limited. Same 220 m
line, same driver, same receiver - only the sample instant changes.

### BIT TIMING DERIVATIONS (16 tq, 1/5/6/4 split, 75% sample point)

| Rate | Bit time | tq | VHDL clock | PROP_SEG | Sample at |
|---|---|---|---|---|---|
| 125 kbit/s | 8.000 us | 500 ns | 2.000 MHz | 2500 ns | 6.000 us |
| 500 kbit/s | 2.000 us | 125 ns | 8.000 MHz | 625 ns | 1.500 us |
| 1 Mbit/s | 1.000 us | 62.5 ns | 16.000 MHz | 312.5 ns | 0.750 us |

### MEASURED - edge launched at t = 10.000 us, arrives 11.1385 us

| Rate | Sample instant | vdb at sample | RX | Verdict |
|---|---|---|---|---|
| 1 Mbit/s | 10.750 us | 1.50e-07 V | 5 V rec | BIT MISSED |
| 500 kbit/s | 11.500 us | 1.996406 V | 0 V dom | reads |
| 125 kbit/s | 16.000 us | 1.996406 V | 0 V dom | reads |

The 1 Mbit/s failure is absolute, not marginal. vdb = 1.5e-07 V means the far
end is still fully recessive: the receiver sampled 388 ns BEFORE the wave
arrived. Transmitter driving dominant, receiver reading recessive, and no
threshold or noise-margin change can fix it. This is the physical mechanism
behind the CAN bit-rate/length trade-off.

I predicted 500 kbit/s would be marginal. It was not - 362 ns of slack after a
~20 ns edge. Over-hedged.

### TWO INDEPENDENT CONSTRAINTS - the real lesson

This netlist tests ONE-WAY RECEPTION only. Arbitration imposes a separate and
stricter round-trip constraint, because a node must transmit recessive and
detect another node dominant WITHIN THE SAME BIT TIME.

  one-way   (reception)   : t_cable < sample instant
  round-trip(arbitration) : 2*(t_cable + t_trx) < PROP_SEG

| Rate | One-way | Round trip | Result |
|---|---|---|---|
| 125 k | 1.114 < 6.000 PASS | 2.271 < 2.500 PASS | works |
| 500 k | 1.114 < 1.500 PASS | 2.271 > 0.625 FAIL | arbitration dies |
| 1 M | 1.114 > 0.750 FAIL | 2.271 > 0.3125 FAIL | both die |

500 kbit/s over 220 m would RECEIVE DATA CORRECTLY and FAIL ARBITRATION
COMPLETELY. Testing reception alone gives a false pass. Day 18 conflated these
two constraints; they are now separated with numbers.

### MAX LENGTH per rate with OUR 5/16 PROP_SEG allocation
  t_cable_max = PROP_SEG/2 - 150 ns (real transceiver), length = t * 2e8

  125 k : 2500/2 - 150 = 1100 ns  -> 220 m
  500 k :  625/2 - 150 = 162.5 ns ->  32.5 m
  1 M   :  312.5/2 - 150 = 6.25 ns ->  1.25 m

Real CAN achieves 100 m at 500 k and 40 m at 1 M. The discrepancy is NOT an
error in this analysis - it shows the 1/5/6/4 split, derived for 125 kbit/s over
a long bus, is wrong for high rates. Real high-rate timing allocates a much
larger PROP_SEG fraction (8/16 or more). The correct conclusion is that the
segment allocation must be re-derived per rate, not that CAN is limited to
1.25 m at 1 Mbit/s.

## Day 22 - Bit timing logic (vhdl/src/bit_timing.vhdl)

First module of Phase 3. Divides each bit into 16 tq, generates the sample point
at tq 12, implements hard sync and resynchronisation with SJW bounding.

### VERIFIED - all 6 checks pass (vhdl/tb/tb_bit_timing.vhdl)

| # | Check | Result |
|---|---|---|
| 1 | free-running bit period | 16 tq |
| 2 | sample point position | tq 12 (75%) |
| 3 | hard sync mid-bit | tq_index -> 0 |
| 4 | edge at tq 3, e=+3 | 19 tq bit |
| 5 | edge at tq 14, e=-2 | 15 tq bit (truncate-to-edge) |
| 6 | edge at tq 9, e=+9, SJW=4 | 20 tq bit, NOT 25 |

### KEY FINDING - resynchronisation is ASYMMETRIC

I had modelled both directions as symmetric. They are not.

  POSITIVE phase error (edge in PROP_SEG or PHASE_SEG1):
    lengthen PHASE_SEG1 by min(e, SJW)
    bit_len = BIT_TQ + corr
    sample point ALSO moves out by corr

  NEGATIVE phase error (edge in PHASE_SEG2):
    TRUNCATE PHASE_SEG2 TO THE EDGE, bounded by SJW.
    bit_len = tq_cnt + 1, NOT BIT_TQ - abs(e).
    The counter is already at tq_cnt when the correction is
    computed, so the bit cannot end before the edge that caused
    it. An edge seen at tq 14 gives a 15 tq bit, not 14.
    The sample point has already passed and does not move.

### BUGS FOUND - 3 failures, only ONE was an RTL bug

1. ELABORATION ERROR: period_valid driven from two processes.
   boolean is UNRESOLVED, so multiple drivers is illegal at
   elaboration. std_logic is resolved and would have been legal.

2. Check 4 got 20, expected 19 - TESTBENCH BUG, not RTL.
   "wait until rising_edge(clk) and tq_index = n" returns AT that
   edge; an assignment after it lands in the NEXT delta, so the
   DUT sees the edge at tq n+1. Injecting at tq 3 was seen at
   tq 4, so e was +4 and a 20 tq bit was CORRECT.
   I rewrote the working RTL TWICE before instrumenting.

3. Check 5 got 16 - GENUINE RTL BUG. Branch priority was
   hard_sync > WRAP > resync. A negative-phase-error edge arrives
   in PHASE_SEG2 near the end of the bit, exactly where the wrap
   condition is already true, so the wrap swallowed the edge and
   the correction never applied. Fixed to hard_sync > RESYNC >
   wrap. This would have survived into the full controller and
   appeared much later as nodes failing to hold sync when running
   fast.

4. Check 5 then got 15, expected 14 - MY EXPECTATION was wrong,
   per the truncate-to-edge rule above.

### PROCESS NOTE
A cycle-by-cycle probe testbench (vhdl/tb/tb_probe.vhdl) resolved
in one run what two rounds of confident reasoning got wrong.
Instrument before theorising.

## Day 23 - Bit stuffing / destuffing (vhdl/src/bit_stuff.vhdl)

After FIVE consecutive identical bits the transmitter inserts one bit of
opposite polarity; the receiver discards it. This guarantees an edge at least
every six bit times, which is what gives the Day 22 resync logic something to
lock onto. The two modules are directly coupled.

### VERIFIED - 5 of 7 planned checks pass

| # | Check | Result |
|---|---|---|
| 1 | no stuffing for runs below 5 | 0 stuff bits |
| 2 | one stuff bit after exactly 5 | 1 bit, opposite polarity |
| 4 | destuffer removes a correct stuff bit | 6 payload from 7 fed |
| 6 | six identical bits | stuff_err raised |
| 7 | stuffing disabled | 0 stuff bits |

### NOT YET VERIFIED - deferred to Day 24
  Check 3: consecutive stuffing (5 identical, stuff, 5 more -> 2nd stuff bit).
           A stuffed bit must RESET the run count to 1, because the stuffed bit
           itself is the first bit of the next run.
  Check 5: ROUND TRIP - stuff a pattern, feed it to the destuffer, assert the
           recovered stream equals the original. This is the check that catches
           stuffer/destuffer disagreement. Both paths are currently verified
           only in ISOLATION. The module is NOT fully verified until this runs.

### SCOPE - where implementations commonly go wrong
Stuffing applies from SOF through the CRC SEQUENCE only. It does NOT apply to
CRC delimiter, ACK slot, ACK delimiter, EOF, or interframe space - those are
fixed-form fields and a stuff bit there is a protocol violation. The module
takes an explicit stuff_en input rather than inferring the field.

### ERROR CONDITION
Six identical bits is a STUFF ERROR. Not an edge case: error frames are
deliberately six dominant bits, so the destuffer must REPORT it rather than
silently resynchronise. Feeds the Phase 5 error handling.

### BUG - the SAME unresolved-signal error as Day 22
err_count and recv_len are INTEGERS driven from both the cap process and stim.
integer is UNRESOLVED, so two drivers is an elaboration error. I had written a
LOG entry about this exact rule the previous day and still repeated it.
Fixed with a clr_counters request signal so cap remains the sole driver.

Rule: a signal gets ONE driver per process, and a process that assigns it
anywhere creates a driver whether or not that branch runs. std_logic is
RESOLVED (a resolution function arbitrates - this is how the wired-AND bus is
modelled). integer, boolean and enumerated types are UNRESOLVED.

### PROCESS NOTE - Day 22 lesson applied successfully
All stimulus driven on the FALLING edge, all sampling on the RISING edge. Both
failure points I predicted in advance (tx_stall registration timing, the
payload-bit count) were fine. The delta-cycle discipline worked.

## Day 24 - Bit stuffing ROUND TRIP (vhdl/tb/tb_stuff_rt.vhdl)

Day 23 verified the stuffer and destuffer in ISOLATION, which cannot catch the
two paths disagreeing. This harness wires them in series:

  payload -> [stuffer] -> stuffed stream -> [destuffer] -> recovered

and asserts recovered = payload bit for bit.

### RESULTS - all 5 patterns recover exactly

| Pattern | Payload | Real stuff bits | Recovered |
|---|---|---|---|
| A alternating 0101... | 12 | 0 | 12 exact |
| B all-dominant | 12 | 2 | 12 exact |
| C all-recessive | 12 | 2 | 12 exact |
| D 5 dom / 5 rec / 5 dom | 15 | 2 | 15 exact |
| E CAN ID 0x0A5 | 11 | 0 | 11 exact |

Pattern B is the decisive one: TWELVE identical bits give TWO stuff bits,
confirming that a stuffed bit RESETS the run counter to 1 (the stuffed bit is
itself the first bit of the next run). If the counter did not reset only one
stuff bit would appear and the destuffer would desynchronise. The isolated
Day 23 checks could not reach this property.

### MY PREDICTION FOR PATTERN D WAS WRONG
I predicted 0 stuff bits for 5 dominant / 5 recessive / 5 dominant, reasoning
that runs of exactly five never reach a sixth identical bit. Wrong: the stuffer
inserts AFTER five identical bits regardless of what follows - it cannot see
ahead. Five dominant -> stuff a recessive -> the payload five recessive bits
then follow that stuffed recessive, making six in a row, so a second stuff bit
is required. Measured 2. The round trip recovering D exactly proves both sides
handle this consistently.

### TWO HARNESS BUGS, BOTH ABOUT REGISTERED OUTPUTS
1. Capture gated only on rising_edge(clk), not on the bit slot. Each slot spans
   two clock edges, so every bit was captured twice: 12 payload -> 27 captured.
   Fixed by qualifying capture with the enable.
2. Capture then taken on the SAME edge as tx_en. tx_bit_out is REGISTERED, so
   the bit appears one clock later - the capture grabbed the previous slot and
   the whole stream shifted by one. Diagnostic showed i=0: sent=0 stuffed=1,
   where 1 is the reset value of tx_out_r. Fixed with a one-clock delayed enable.

The DUT was correct throughout. This is the THIRD consecutive day where the RTL
was right and my testbench was wrong (Day 22 delta-cycle, Day 23 unresolved
signal, Day 24 registered-output capture x2). Default hypothesis on a failure
should now be "the testbench is wrong".

### DRAIN SLOT
round_trip feeds one extra bit after the payload loop, so stuffed_len is always
payload + real stuff bits + 1. The reported count now subtracts it. Without that
correction A and E showed 1 insertion where zero stuffing is possible.

## Day 25 - CRC-15 (vhdl/src/crc15.vhdl, tools/crc15_ref.py)

Generator polynomial x^15+x^14+x^10+x^8+x^7+x^4+x^3+1 = 0x4599.

  msb = crc(14); crc = crc(13 downto 0) & Z0Z; if (msb xor bit) then crc ^= POLY

Register initialises to ZERO, so an all-zero input must give an all-zero CRC.

### RESULT: 417 of 417 vectors match, ZERO mismatches

Verified against tools/crc15_ref.py, an INDEPENDENT Python model written from
the ISO 11898-1 definition rather than from the RTL. Deriving the reference from
the VHDL would make both share any misunderstanding and agree while both wrong.

Vector set (seed 20260812, fully reproducible):
  - 8 targeted edge cases: all-zero, MSB-only, LSB-only, all-ones, alternating,
    15-bit width (same as the register), single 1, single 0
  - 9 frames using the frozen node IDs 0x0A5 / 0x123 / 0x2AA at DLC 0, 1, 8
  - 200 random realistic CAN frames (random ID, RTR, DLC, data)
  - 200 random bit strings of length 1-99

Sanity values from the reference:
  all-zero x19      -> 0000   (must be zero, catches a register that never resets)
  MSB only x19      -> 4B62
  all-ones x19      -> 4ECB
  ID 0x0A5 DLC 0    -> 45A4
  ID 0x0A5 DLC 1 5A -> 59FE

### COVERAGE
SOF, identifier, RTR, IDE, r0, DLC, data field. Stops before the CRC sequence.
CRITICAL: computed on DESTUFFED bits. Stuff bits are a physical-layer artefact
and are never included; computing the CRC over the stuffed bus stream yields a
value the receiver can never match.

### THREE TESTBENCH ISSUES (RTL was correct throughout - 4th day running)
1. ieee.std_logic_textio is a Synopsys extension needing -fsynopsys. Removed:
   only read(line,integer) and read(line,character) were used, both in std.textio.
2. Slicing a function result: hex2slv returned an UNCONSTRAINED
   std_logic_vector, so the string literal indexes ASCENDING (0 to 3), and
   slicing it (2 downto 0) is a direction mismatch at runtime. Fixed by
   concatenating all four nibbles into a declared descending 16-bit variable
   and slicing that.
3. TIMEOUT MASQUERADING AS PASS - the important one. At 200 ns per bit and
   ~20850 bits the run needs 4.334 ms; a 3 ms stop-time truncated it at roughly
   vector 290. No summary printed, nothing asserted, and run.sh reported PASS.
   Added a timeout guard process that asserts if the stimulus has not set done.

   GENERAL HAZARD: every GHDL run in this project uses a fixed stop-time and
   could in principle be silently truncated. Earlier runs all printed their
   final PASSED line so they genuinely completed, but that was luck. Future
   testbenches should carry a completion guard.

## Day 26 - Frame generator (vhdl/src/frame_gen.vhdl, tools/frame_ref.py)

Assembles a complete standard CAN data frame and emits one bit per bit_en pulse,
driving crc15 as a submodule. First point where verified modules run as a system.

### RESULT: 68 of 68 frames bit-exact, zero stuff_en mismatches

Checked against tools/frame_ref.py, written from ISO 11898-1 and not from the
RTL. Every bit AND every stuff_en value compared.

Vector set (seed 20260813): frozen node IDs 0x0A5 / 0x123 / 0x2AA at DLC 0,
DLC 1 and DLC 8 on the primary ID, all-zero ID+data (max dominant run), all-ones
ID+data (max recessive run), an RTR frame, and 60 random frames.

### FRAME LAYOUT AND STUFF SCOPE

| Field | Bits | Stuffed |
|---|---|---|
| SOF | 1 | yes |
| Identifier | 11 | yes |
| RTR | 1 | yes |
| IDE | 1 | yes |
| r0 | 1 | yes |
| DLC | 4 | yes |
| Data | 0-64 | yes |
| CRC sequence | 15 | yes |
| CRC delimiter | 1 | NO |
| ACK slot | 1 | NO |
| ACK delimiter | 1 | NO |
| EOF | 7 | NO |
| IFS | 3 | NO |

DLC=0: 44 frame bits + 3 IFS = 47 emitted, 34 stuffed
DLC=8: 108 frame bits + 3 IFS = 111 emitted, 98 stuffed

Hand-verified frame for ID 0x0A5 DLC 0:
  00001010010100000001000101101001001111111111111
  SOF=0 | ID=00010100101 (0x0A5) | RTR=0 | IDE=0 | r0=0 | DLC=0000
  | CRC=100010110100100 (0x45A4) | delim=1 | ACK=1 | delim=1
  | EOF=1111111 | IFS=111
stuff_en high for bits 0-33 (34 bits), dropping exactly at the CRC delimiter.
CRC 0x45A4 matches the Day 25 reference value for the same frame - two
independently written models agreeing.

### DESIGN CORRECTION - frame_active must drop at END OF EOF
I initially held frame_active through IFS. Interframe space is NOT part of the
frame: the frame ends after EOF, and IFS is the mandatory gap BEFORE the next
frame, during which the bus is IDLE and any node may start transmitting.
Holding frame_active through IFS would block arbitration for 3 bit times in
Phase 4. Fixed in both the RTL and the reference model.

### THE STUFF BOUNDARY
stuff_en is high from SOF through the LAST CRC bit and low from the CRC
delimiter onward. One bit either way corrupts every frame. Verified bit-exactly
across all 68 frames rather than left as a comment.

### CRC COVERAGE
crc_en is asserted only from SOF through the end of the data field. The CRC does
NOT cover itself, and does not cover any field after it. Because frame_gen emits
payload bits with the stuffer downstream, the CRC is automatically computed on
DESTUFFED bits.

### THE ONLY BUG - my file parser, again (5th day running)
When data bytes are present the parse loop consumes the trailing space via
"exit when ch = Z Z", then an unconditional read(vline, space) swallowed the
first digit of nbits - 55 parsed as 5. That misaligned the expected bit and
stuff strings and produced a nonsensical stuff_en=0 expectation inside the
identifier field. The asymmetry was the trap: the no-data branch reads one
character and LEAVES the separator; the hex branch reads THROUGH it. Both then
ran the same cleanup.

All three RTL failure points I predicted in advance - the ST_CRC latch timing,
the DLC=0 direct path, and the data-field bit indexing - were correct first run.
Frames 1-3 passed completely before the parser broke on frame 4, which localised
it immediately.

### REPO HYGIENE
Added .gitignore for vhdl/*_vectors.txt, vhdl/*.vcd and vhdl/work-obj93.cf, and
untracked crc_vectors.txt. Generated artefacts are reproducible from the tools
with fixed seeds and do not belong in the repo.

## Day 27 - Transmit datapath integration (vhdl/src/can_tx_path.vhdl)

Wires bit_timing, frame_gen, crc15 and bit_stuff into a complete transmit path.
First integration in the project, and the first back-pressure relationship.

### RESULT: 6 of 6 frames bit-exact on the bus at 125 kbit/s

| Frame | Payload | Stuff bits | Bus bits |
|---|---|---|---|
| 1 ID 0x0A5 DLC 0 | 47 | 1 | 48 |
| 2 ID 0x123 DLC 0 | 47 | 1 | 48 |
| 3 ID 0x2AA DLC 0 | 47 | 2 | 49 |
| 4 ID 0x0A5 DLC 1 | 55 | 2 | 57 |
| 5 ID 0x0A5 DLC 8 | 111 | 2 | 113 |
| 6 all-zero DLC 8 | 111 | 16 | 127 |

Frame 6 is decisive: an all-zero 8-byte payload needs 16 stuff bits, every one
correctly placed with no payload bit lost. Timing measured 1.040 ms for 127 bits,
against 1.016 ms theoretical at 8.000 us per bit - real 125 kbit/s.

### TWO GENUINE RTL BUGS, BOTH INVISIBLE TO ISOLATED TESTING

1. RUN-COUNTER OVERFLOW (bit_stuff). The fixed-form fields at the end of a frame
   are 13 consecutive recessive bits - CRC delimiter, ACK, ACK delimiter, 7 EOF,
   3 IFS - transmitted with stuffing DISABLED. Nothing reset the run counter, so
   it climbed past its 1..8 range and hit a bound check. Isolated tests only ever
   exercised enabled runs. Fixed by clearing the count when stuffing is disabled
   and clamping it: at STUFF_LEN on the transmit side, at STUFF_LEN+1 on the
   receive side so six identical bits can still raise stuff_err.

2. LATE BACK-PRESSURE (bit_stuff -> frame_gen). tx_stall was REGISTERED, so it
   became valid one clock AFTER the slot it described. By then frame_gen had
   already advanced, dropping exactly one payload bit per stuff bit. Added a
   combinational tx_stall_c computed from settled state and drove frame_gen hold
   from that instead.

   This is the classic integration failure: both modules individually correct,
   the fault entirely in the handshake between them.

### THE COST - a self-inflicted testbench spiral
I wrote a bit destuffer inside the testbench to recover the payload from the bus
stream. It was wrong four separate ways and consumed most of the day. The right
move, taken far too late, was to have frame_ref.py emit the expected STUFFED bus
stream and compare against it directly. That worked immediately.

RULE: when a reference model exists, never reimplement its inverse in the
testbench. Compare against what the model already produces.

Also of note: after five consecutive days where the RTL was correct and my
testbench was not, I had stopped seriously considering that the DUT might be
wrong. Today it was wrong twice. The fix was to compare the captured stream
against the PAYLOAD directly, which located the dropped bit in one run.

### OTHER ISSUES
- VHDL-93 port maps require static names, not expressions. A gated enable needs
  its own signal.
- A spurious PASS: the compare loop only checked positions 1..nbits, so an extra
  48th bit went unexamined. Fixed by checking the full bus length.
- The capture window overruns the frame by one idle slot, so the length check
  now requires the captured stream to CONTAIN the expected one from SOF, with
  trailing recessive slots allowed - which is what a real receiver sees.
