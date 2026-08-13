# CAN Project Log

## Day 1
- Disk: 93G total, 64G free
- Toolchain verified: XSPICE bridges 5.000/0.000 V, RC 1-tau 0.6321209, ghdl.cm loaded via spinit
- Project root: ~/Documents/CAN_project
- Directory tree + git initialised

## Day 2 - toolchain gate CLEARED
- NGHDL end-to-end verified standalone (no eSim needed)
- customblock PWM: duty_boost 4.507284 V (pred 4.5, err 0.16%), duty_buck 0.5002 V (pred 0.5, err 0.04%)
- Fixed 3 bugs: PyQt5 missing; eSim attr_microcontroller UnboundLocalError; NGHDL start_server.sh glob-order dependency bug (locale dependent)
- Patches committed: patch_esim_microcontroller.py, patch_nghdl_ghdl_order.py

## Day 3 - NGHDL capability probes
- Probe A: std_logic_vector ports WORK (probe_vec.xml: node_number 2, split 4-V:1-V)
- Probe B: multiple instances WORK and independent (q1/q2 complementary, 5.000/0.000 V exact)
- DECISION: Approach B locked - one can_node model, node_sel(1:0), instance_id per node
- NGHDL parser is formatting-sensitive: ports must follow customblock style
- Benchmark: 1 instance @ 2 MHz over 1.5 ms = 4.9 s -> 16 tq / 2 MHz CONFIRMED viable
- Patched: GTKWave auto-launch disabled in generator and existing scripts

## Day 6 - VHDL fundamentals I
- run.sh development loop built and working (edit -> test in ~2 s)
- counter.vhdl: clocked process, async reset, unsigned vs std_logic_vector
- tb_counter.vhdl: 4 self-checking asserts, all pass
- Verified signal-assignment delay: a lags cnt by 1 clock, b lags a by 1 clock

## Day 7 - VHDL fundamentals II (FSM)
- fsm_serial.vhdl: 4-state Moore FSM, miniature CAN-like frame (SOF + 8 data MSB-first + 3 EOF)
- tb_fsm_serial.vhdl: verifies all 12 output bits individually, named per field
- Confirmed testbench detects a deliberate single-bit payload error (exit code 1)
- Pattern established for can_tx_fsm: enum state type, case in clocked process, when others, Moore outputs concurrent

## Day 8 - VHDL fundamentals III (vectors, conversions, shift registers)
- shift11.vhdl: 11-bit parallel-load MSB-first shift register
- Verified with Node A CAN ID 0x0A5 - all 11 bits correct in serial order
- Slicing/concatenation, integer<->unsigned<->std_logic_vector conversion at port boundary

## Day 10 - hierarchy and port map (Phase 1 complete)
- frame_tx.vhdl: FSM instantiating shift11, transmits SOF + 11-bit ID + EOF
- Verified 15-bit stream for two different IDs (0x0A5, 0x123) - 30 bits checked
- run.sh rewritten to use GHDL make mode (ghdl -i + ghdl -m) - resolves dependency order automatically, required for can_node with 8 submodules
- Learned: label is a VHDL reserved word; also entity signal block bus register open range severity report next exit new access
- Phase 1 complete 2 days early (Day 9 satisfied throughout, Day 11 UART redundant with fsm_serial)

## Day 13 - analog PHY DC verification
- phy_dc.cir: single driver, dual 120 ohm termination, 10k bias network
- All dominant quantities within 0.2% of prediction; R_on = 45 ohm CONFIRMED
- Found and fixed modelling artefact: 1M leak resistors shifted recessive level by -25 mV; raised to 100M (error now -0.25 mV)

## Day 14 - PHY receiver and loopback
- Added tanh comparator, adc/dac bridges, inverting driver control
- Full TX->bus->RX loopback verified, polarity correct through both inversions
- Loop delay 35.4 ns (budget 150 ns); bit period exactly 8.000 us
- Measurement-point error found: PULSE(5 0 10u 20n 20n 4u 8u) is dominant 10-14us and 18-22us, so t=20us was NOT recessive. Circuit was correct, the probe point was wrong.

## Day 15 - edge rates and capacitance sweep
- Swept C_bus 100pF..10nF, measured differential 10-90% edge
- Linear relationship confirmed, all points within 0.7% of prediction
- Project value 1 nF gives 39.761 ns (predicted 39.6 ns)
- Practical loading limit identified: 10 nF -> 397 ns edge = 79% of one tq
- Note: dac_bridge 20 ns transition does NOT contaminate the measurement; the switch flips on threshold crossing rather than tracking the ramp

## Day 16 - wired-AND demonstration [KEY RESULT A8]
- Three drivers on one bus, all 8 input combinations measured
- Bus recessive in exactly one case: bus = TX_A AND TX_B AND TX_C confirmed electrically
- Multi-driver Vdiff 0 / 1.9964 / 2.8535 / 3.3300 V, all within 0.2% of prediction
- Vdiff counts the number of active transmitters - the physical basis of arbitration
- This is the evidence that makes Day 66 arbitration meaningful rather than just a logic result

## Day 17 - transmission line and propagation delay
- 220 m twisted pair modelled with T element, Z0 = 120 ohm, TD = 1.1 us
- Measured propagation 1.113567 us against 1.100 us predicted (+1.2%, edge crossing)
- Round trip 2.2704 us against PROP_SEG 2.500 us: 9.2% margin, small by design
- PROP_SEG = 5 tq now justified by measurement rather than assumption
- No reflections with matched 120 ohm terminations, as Gamma = 0 predicts

## Day 18 - reflections and termination mismatch
- Gamma = (R_L-Z0)/(R_L+Z0) confirmed to <0.25% for open, 1k, 120, 60 ohm
- Open far end doubles to 3.993 V; 60 ohm inverts and reduces to 1.331 V
- Using measured driver output (1.9964 V) reproduces all peaks to 4 sig figs
- RX reads dominant at the sample point in ALL cases, worst margin 70%
- Established WHY the sample point is at 75%: it is one round trip after the edge
- My prediction that 500 pF would blunt the open-circuit peak was wrong - tau=60ns
  is negligible against the 1.1 us transit

## Day 19 - common-mode rejection
- Rev A was WRONG: offset applied only to the 10k bias net, driver clamped it 222:1
- Diagnosed from the data - 0.108 V span for 24 V sweep IS 10000/45
- Rev B references all of node B to gnd_b; offset then genuinely lifts node B
- Node B common mode swings 23.89 V while differential is IDENTICAL to 7 digits
- Rejection is exact by algebra, limited only by component mismatch
- CMRR with 1% R / 5% C = 33.3 dB referred to actual CM (55.7 dB to source)
- Input-range violation at +/-12 V documented as a model limitation: real
  transceivers saturate there, tanh comparator does not
- Both netlists kept - the broken one documents a real and instructive mistake

## Day 20 - multi-bit-rate validation
- Day 18 prediction CONFIRMED: 1 Mbit/s over 220 m misses the bit entirely
- vdb = 1.5e-07 V at the 1 Mbit/s sample point - sampled 388 ns before arrival
- 500 kbit/s and 125 kbit/s both read 1.996406 V correctly (one-way)
- I predicted 500 k would be marginal; it had 362 ns slack. Over-hedged.
- KEY: separated the one-way reception constraint from the round-trip
  arbitration constraint. 500 k over 220 m receives fine but arbitration is
  impossible (round trip 2.27 us > 2.00 us bit time)
- Derived max length per rate for our 5/16 PROP_SEG: 220 m / 32.5 m / 1.25 m
- Documented why these fall short of real CAN: allocation must be re-derived
  per rate, real high-rate timing uses a much larger PROP_SEG fraction

## Day 21 - PHY documentation freeze
- Consolidated Days 13-20 into docs/phy_spec.md as a frozen specification
- All parameters, canonical models, derivations, and verified results in one place
- Model limitations stated explicitly: no CM input range on the tanh comparator,
  transceiver too fast (21.6 ns vs 100-255 ns real), ideal lossless line,
  tolerances modelled in one test only, no bus faults or EMI
- Wrote spice/run_phy_regression.sh - re-runs 4 netlists, checks 17 measurements
  against frozen values at 0.1% (voltage) and 1% (time) tolerance
- Interface contract for the VHDL controller recorded: 2 MHz clock, 16 cycles per
  bit, sample at cycle 12, tx/rx polarity, 35 ns loop delay, wired-AND bus
- PHY IS NOW FROZEN. Phase 3 (CAN controller) begins.

## Day 22 - bit timing logic (Phase 3 begins)
- bit_timing.vhdl: 16 tq per bit, sample at tq 12, hard sync + resync with SJW
- All 6 self-checking tests pass: 16 / tq12 / hardsync / 19 / 15 / 20
- Check 6 (SJW cap) gives 20 not 25 - the cap is real and verified
- KEY: resync is ASYMMETRIC. Positive error lengthens PHASE_SEG1 by min(e,SJW);
  negative error TRUNCATES PHASE_SEG2 to the edge (bit_len = tq_cnt+1), it does
  NOT subtract |e| from the nominal length
- One genuine RTL bug: wrap had priority over resync, swallowing every
  negative-phase-error edge. Fixed to hard_sync > resync > wrap
- Two false alarms: a testbench delta-cycle error and a wrong expected value.
  I rewrote correct RTL twice before instrumenting. Added tb_probe.vhdl
- Learned: boolean/integer are UNRESOLVED, two drivers = elaboration error

## Day 23 - bit stuffing / destuffing
- bit_stuff.vhdl: insert after 5 identical bits, discard on receive, flag 6 as error
- 5 of 7 checks pass: no-stuff-below-5, one-stuff-at-5, discard, error, disabled
- DEFERRED to Day 24: consecutive stuffing and the full ROUND TRIP. Both paths
  are currently verified only in isolation - not fully verified until round trip
- Explicit stuff_en input: stuffing covers SOF..CRC only, not the fixed-form
  fields (CRC delim, ACK, EOF, interframe)
- Repeated the Day 22 unresolved-signal bug on err_count/recv_len despite having
  logged the rule the day before. Fixed with a clear-request signal
- Falling-edge stimulus / rising-edge sampling worked: both predicted failure
  points came out clean on the first run
- Removed bt_fix.py and bt_fix2.py from the repo; patch scripts now go to /tmp

## Day 24 - bit stuffing round trip
- Wired stuffer -> destuffer in series, asserted recovered = payload bit for bit
- All 5 patterns exact: alternating(0), all-dom(2), all-rec(2), 5/5/5(2), ID(0)
- Pattern B decisive: 12 identical bits -> 2 stuff bits, proving the run counter
  resets on a stuffed bit. Isolated Day 23 tests could not reach this
- My Pattern D prediction of 0 stuff bits was wrong: the stuffer inserts after
  five identical bits regardless of what follows, so the stuffed recessive plus
  five payload recessive bits forces a second stuff bit. Measured 2
- Two harness bugs, both registered-output mistakes: captured every clock instead
  of every slot (12 -> 27 bits), then captured one cycle too early (whole stream
  shifted by one, first bit was tx_out_r reset value)
- THIRD straight day the RTL was correct and my testbench was not. Treating
  "testbench is wrong" as the default hypothesis from here
- bit_stuff.vhdl is now FULLY verified - Day 23 checks 3 and 5 are closed

## Day 25 - CRC-15
- crc15.vhdl: LFSR with polynomial 0x4599, register init 0
- 417 of 417 vectors match an INDEPENDENT Python reference, zero mismatches
- Reference written from the ISO definition, not from the RTL, so the two can
  genuinely disagree. 400 random vectors plus 8 targeted edge cases
- All-zero input gives 0000 as it must; ID 0x0A5 DLC 0 gives 45A4
- CRC runs on DESTUFFED bits only - stuffed-stream CRC is unmatchable
- Found a real verification hazard: a 3 ms stop-time truncated the run at about
  vector 290, printed no summary, asserted nothing, and run.sh said PASS.
  Added a timeout guard. Every fixed-stop-time run in this project shares this
  risk
- Two more VHDL gotchas: std_logic_textio needs -fsynopsys (dropped it), and
  slicing an unconstrained function result mixes index directions

## Day 26 - frame generator
- frame_gen.vhdl assembles a full standard CAN frame, drives crc15 as a submodule
- 68 of 68 frames bit-exact against an independent reference, zero stuff_en errors
- Covers DLC 0-8, all-zero and all-ones payloads, RTR, and 60 random frames
- Hand-verified the ID 0x0A5 DLC 0 frame field by field; CRC 0x45A4 matches the
  Day 25 reference value, so two independent models agree
- DESIGN FIX: frame_active now drops at the end of EOF, not after IFS. IFS is not
  part of the frame - the bus is idle during it and any node may transmit.
  Holding it high would have blocked arbitration for 3 bit times in Phase 4
- Stuff boundary verified bit-exactly: high SOF..last CRC bit, low from the CRC
  delimiter onward
- Only bug was my file parser: after reading a hex data token the loop had
  already consumed the separator, so an extra read swallowed a digit of nbits
  (55 -> 5). All three predicted RTL failure points were correct first run
- Gitignored generated vectors and VCDs; untracked crc_vectors.txt

## Day 27 - transmit datapath integration
- can_tx_path.vhdl wires bit_timing + frame_gen + crc15 + bit_stuff
- 6 of 6 frames bit-exact on the bus, verified against the stuffed reference
- Frame 6 (all-zero DLC 8) needed 16 stuff bits, all correctly placed
- Measured 1.040 ms for 127 bits = real 125 kbit/s
- RTL BUG 1: bit_stuff run counter overflowed on the 13 recessive fixed-form
  bits at frame end, where stuffing is disabled and nothing reset it
- RTL BUG 2: tx_stall was registered so it arrived a clock late; frame_gen had
  already advanced and dropped one payload bit per stuff bit. Added a
  combinational tx_stall_c for the back-pressure path
- Both bugs were invisible to isolated testing - this is what integration is for
- COST: I wrote a destuffer in the testbench, got it wrong four ways, and burned
  most of the day. The reference model should have emitted the expected stuffed
  stream from the start. RULE: never reimplement a reference model inverse
- After five days of "it is always the testbench" I had stopped considering the
  DUT could be wrong. Today it was, twice

## Day 28 - receive path decoder (Phase 4 begins)
- frame_rx.vhdl decodes the bus stream back to ID / RTR / DLC / data
- 20 of 20 frames decoded correctly against the reference vectors
- All 3 error paths verified: crc_err on a flipped bit, form_err on a dominant
  EOF bit, stuff_err on six identical bits
- Closes the loop with Day 27: TX builds these streams, RX decodes them back
- RTL BUG: remote frames left the PREVIOUS frame data in rx_data, because an
  RTR frame has no data field and nothing cleared it. Fixed by clearing at SOF.
  Only surfaced because an all-ones frame preceded the RTR frame in the vectors
- RTL BUG: third bit_stuff counter overflow, this time in the stuff-error branch.
  Same class as the other two - fine on well-formed input, runs away on a path
  the isolated tests never reached. Clamped at STUFF_LEN+1 so six identical bits
  can still be detected
- VHDL: identifiers are CASE-INSENSITIVE, so state RX_ID collided with port
  rx_id. Renamed states to S_*
- VHDL: case expressions need a locally static subtype, so a concatenation must
  go through a variable first
- stuff_en driven combinationally from state, per the Day 27 lesson
- STILL MISSING: ACK generation, error frames, abort on stuff_err

## Day 29 - ACK generation and TX/RX loopback
- Receiver drives dominant in the ACK slot when the CRC matched; transmitter
  samples the slot and reports ack_ok / ack_err
- Wired-AND bus in VHDL: bus <= tx and (not ack_drive), matching the Day 16 SPICE
- Test 1 (receiver present): ack_drive asserted, bus went dominant, ack_ok
- Test 2 (receiver in reset): ack_err. This is the discriminating test - an ACK
  check that always succeeds passes test 1 identically
- crc_ok must be computed at the END of the CRC field, since the ACK slot is only
  two bits later. ack_drive is combinational so it is valid during the one-bit
  slot
- My independent bus capture was initially keyed off the TRANSMITTER field_id,
  one slot away from the wire, and reported recessive in both tests. Re-keyed off
  the receiver ack_drive. A pass that contradicts an independent observation is
  not a pass
- run.sh needs a matching src module, so integration testbenches (tb_probe,
  tb_stuff_rt, tb_ack) are run via ghdl directly. Worth a run_tb.sh eventually

## Day 30 - arbitration
- Three nodes contending on a wired-AND bus; lowest identifier wins
- 4 of 4 contests correct: A alone, A vs B, A vs B vs C, and B vs C with A absent
- Test 4 (B vs C) is the discriminating one - proves the winner comes from the
  identifiers present, not from node A never losing by construction
- BUG: the check was inside frame_gen comparing the PRE-STUFFING payload bit
  against the POST-STUFFING bus, so an inserted stuff bit looked like a lost
  arbitration. Node A lost against an empty bus
- Arbitration is a property of the WIRE: compare what was physically driven
  against what came back. Moved the check to can_tx_path, which sees both;
  frame_gen now takes an arb_abort input
- Test 1 (single node) caught it instantly - keep trivial-looking tests, they
  separate "fires when it should not" from "picks the wrong winner"
- Comparison happens at the sample point, which is why PROP_SEG exists: at 220 m
  a competing dominant bit needs 1.11 us to arrive (Day 17)
- SIMPLIFICATION: nodes share a clock and start aligned. Independent oscillators
  with resync is a separate test

## Day 31 - can_node wrapper and two-node bus
- can_node.vhdl: complete node - TX path, RX chain, ACK gating, bus contribution
- 4 of 4 tests pass FIRST RUN with no bugs. First clean day of the project,
  because every submodule was verified in isolation first
- Test 3: both nodes transmit, node 1 loses arbitration AND still receives
  node 0 frame intact - non-destructive arbitration confirmed end to end
- Test 4: with node 1 absent, node 0 reports tx_noack. A transmitter must not
  ACK its own frame or the whole no-ACK detection path is dead
- One bit_timing per node drives both directions; self-reception is deliberate
  and is how arbitration and ACK monitoring work
- PHASE 4 SUBSTANTIALLY DONE: TX, RX, arbitration, ACK all working between nodes
- REMAINING for protocol completeness: error frames, TEC/REC, bus-off,
  retransmission after arbitration loss (Phase 5)
- can_node has a flat port list = NGHDL ready. Roadmap puts mixed-signal at
  Day 59; pulling it forward would retire the biggest remaining unknown early

## Day 32 - MIXED-SIGNAL CAN WORKING (Day 59 milestone, reached on Day 32)
- Two VHDL CAN controllers as NGHDL models on the real analog PHY
- Node 0 (0x0A5) won arbitration, node 1 (0x123) detected the loss at 57 us,
  node 0 frame acknowledged at 385 us, node 1 received it at 455 us
- The wired-AND is now PHYSICAL: two 45 ohm drivers on one 120 ohm pair, with
  arbitration decided by reading back an analog level through the comparator
- Runtime 5.7 s for 600 us with 2 nodes, nearly all socket wait (user 0.007 s).
  Four nodes is practical. LARGEST PROJECT RISK RETIRED
- UPSTREAM BUG 5: NGHDL could not build multi-file VHDL models. Fixed with GHDL
  make mode; 12 files now analyse in dependency order in 0.79 s. Also subsumes
  the Day 11 locale patch
- UPSTREAM BUG 6: the entity parser scans comments for "port" and "end". Our
  comment said "reformat the port list" and broke the parse. Stripped comments
  from the NGHDL copies
- MY ERROR: digital event nodes are NOT analog vectors. meas tran v(busy0_d)
  silently returns 0. Must tap through a dac_bridge first - Day 11 did this and
  I did not carry it forward. Nearly concluded the design was broken
- NGHDL "Add Files" does copy dependencies; only the build script was limited
