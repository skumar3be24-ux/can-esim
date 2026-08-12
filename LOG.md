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
