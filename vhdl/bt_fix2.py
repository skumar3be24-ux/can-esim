import sys

# ---------------------------------------------------------------
# Day 22 - correcting the NEGATIVE phase error case.
#
# Established by tb_probe:
#   edge seen at tq 14, e = -2, DUT produced a 15 tq bit.
#
# Is 15 right? Yes. Shortening PHASE_SEG2 truncates the segment
# TO THE EDGE, it does not subtract |e| from the nominal length.
# The counter is already at 14 when the correction is computed,
# so the earliest the bit can end is there: 15 quanta.
# Producing 14 would require ending the bit BEFORE the edge that
# triggered the shortening, which is impossible.
#
# ISO 11898-1: on an edge in PHASE_SEG2 the bit ends at the edge,
# bounded by SJW. So:
#     bit_len = tq_cnt + 1        (end here)
#     but the shortening (BIT_TQ - bit_len) must not exceed SJW
#
# The rev C RTL used "if tq_cnt >= BIT_TQ - corr - 1" which
# conflates the SJW bound with the termination point. Replaced
# with an explicit form.
# ---------------------------------------------------------------

p = 'src/bit_timing.vhdl'
s = open(p).read()

old = """        elsif e < 0 then
          -- shorten PHASE_SEG2 by min(|e|, SJW).
          -- The sample point has already passed, so only the tail
          -- shortens. If the shortened bit ends at or before the
          -- current count, terminate the bit NOW.
          if (-e) > SJW then corr := SJW; else corr := -e; end if;
          if tq_cnt >= BIT_TQ - corr - 1 then
            tq_cnt     <= 0;
            bit_len    <= BIT_TQ;
            samp_at    <= END_PHASE1 - 1;
            did_resync <= '0';
            bitst_r    <= '1';
          else
            bit_len    <= BIT_TQ - corr;
            did_resync <= '1';
            tq_cnt     <= tq_cnt + 1;
          end if;
"""

new = """        elsif e < 0 then
          -- ---- shorten PHASE_SEG2: truncate the segment TO the edge ----
          -- ISO 11898-1: an edge in PHASE_SEG2 ends the bit AT the
          -- edge, bounded by SJW. It does NOT subtract |e| from the
          -- nominal length. The counter is already at tq_cnt when the
          -- correction is computed, so the bit cannot end earlier than
          -- here - ending at tq_cnt gives a bit of tq_cnt+1 quanta.
          -- (Established with tb_probe: edge at tq 14 -> 15 tq bit.)
          if (-e) > SJW then corr := SJW; else corr := -e; end if;
          if (BIT_TQ - (tq_cnt + 1)) <= SJW then
            -- shortening is within SJW: end the bit now
            tq_cnt     <= 0;
            bit_len    <= BIT_TQ;
            samp_at    <= END_PHASE1 - 1;
            did_resync <= '0';
            bitst_r    <= '1';
          else
            -- shortening would exceed SJW: clamp, run to BIT_TQ-SJW
            bit_len    <= BIT_TQ - SJW;
            did_resync <= '1';
            tq_cnt     <= tq_cnt + 1;
          end if;
"""

assert old in s, 'RTL pattern not found'
open(p, 'w').write(s.replace(old, new))
print('RTL: negative-phase-error case now truncates to the edge')

# ---------------------------------------------------------------
# Testbench: Check 5 expected 14, which was wrong for the reason
# above. An edge seen at tq 14 correctly yields a 15 tq bit.
# ---------------------------------------------------------------

p2 = 'tb/tb_bit_timing.vhdl'
t = open(p2).read()

old5 = """    -- edge at tq 14 -> e = 14-16 = -2 -> PHASE_SEG2 -2 -> bit = 14 tq
    resync_at(14, got);
    assert got = 14
      report "FAIL: after -2 resync bit was " & integer'image(got)
             & " tq, expected 14"
      severity error;"""

new5 = """    -- Edge SEEN at tq 14 -> e = -2. PHASE_SEG2 is truncated TO the
    -- edge, so the bit ends at index 14 = 15 quanta. It is NOT
    -- 16-2=14: the counter is already at 14 when the correction is
    -- computed, so the bit cannot end earlier than there.
    -- Shortening = 16-15 = 1 tq, within SJW=4.
    resync_at(14, got);
    assert got = 15
      report "FAIL: after -2 resync bit was " & integer'image(got)
             & " tq, expected 15 (truncate-to-edge, not 16-|e|)"
      severity error;"""

assert old5 in t, 'testbench Check 5 pattern not found'
t = t.replace(old5, new5)

t = t.replace(
  'report "PASS: -2 resync gave a " & integer\'image(got) & " tq bit"',
  'report "PASS: -2 resync truncated to a " & integer\'image(got) & " tq bit"'
)

open(p2, 'w').write(t)
print('testbench: Check 5 now expects 15 (truncate-to-edge)')
