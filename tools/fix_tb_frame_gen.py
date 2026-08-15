#!/usr/bin/env python3
"""
Repair the stale frame_gen testbench.

tb_frame_gen.vhdl was written on Day 26. frame_gen later gained
bus_bit and sample_en (Day 29, acknowledgement), arb_abort and
in_arb (Day 30, arbitration), and hold (Day 27, stuffer
back-pressure). The testbench was never updated, so it no longer
compiles.

The new inputs are tied to values that reproduce the conditions the
test was written for: no stuffer back-pressure, no arbitration
abort, no sample-point events, and a recessive bus. That isolates
the frame generator exactly as intended.
"""
import re

P = ('/home/vboxuser/Documents/CAN_project/vhdl/tb/tb_frame_gen.vhdl')
s = open(P).read()

if 'arb_abort =>' in s:
    print("already repaired")
    raise SystemExit(0)

old = """      bit_en => bit_en, tx_bit => tx_bit,"""
new = """      bit_en => bit_en,
      -- inputs added after this testbench was written (Days 27-40).
      -- Tied off to reproduce the Day 26 conditions: no stuffer
      -- back-pressure, no arbitration abort, no sample events, bus
      -- recessive.
      hold      => '0',
      bus_bit   => '1',
      sample_en => '0',
      arb_abort => '0',
      in_arb    => open,
      tx_bit => tx_bit,"""

if old not in s:
    # fall back: find the port map and show it
    m = re.search(r'dut : entity work\.frame_gen\s*\n\s*port map \((.*?)\n\s*\);',
                  s, re.S)
    print("expected mapping not found. Current port map:\n")
    print(m.group(1) if m else "(port map not located)")
    raise SystemExit(1)

s = s.replace(old, new, 1)

# the newer outputs also need somewhere to go
s = s.replace("      field_id => field_id\n",
              "      field_id => field_id,\n"
              "      arb_lost => open,\n"
              "      ack_ok   => open,\n"
              "      ack_err  => open\n", 1)

open(P, 'w').write(s)
print("repaired tb_frame_gen.vhdl")
