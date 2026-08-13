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
