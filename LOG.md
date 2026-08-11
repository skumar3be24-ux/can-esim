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
