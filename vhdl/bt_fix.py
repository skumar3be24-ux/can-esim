import sys

p = 'src/bit_timing.vhdl'
s = open(p).read()

# ---------------------------------------------------------------
# Fix: branch priority was hard_sync > WRAP > resync.
# An early-edge resync (negative phase error) arrives in
# PHASE_SEG2, near the end of the bit - exactly where the wrap
# condition is already true. The wrap therefore swallowed the
# edge and the correction was never applied.
#
# Correct priority is hard_sync > RESYNC > wrap, and a resync
# that shortens the bit below the current count must end the
# bit immediately.
# ---------------------------------------------------------------

old = """      elsif tq_cnt >= bit_len - 1 then
        -- ---------- end of bit: wrap ----------
        -- checked BEFORE resync so a wrap always wins
        tq_cnt     <= 0;
        bit_len    <= BIT_TQ;
        samp_at    <= END_PHASE1 - 1;
        did_resync <= '0';
        bitst_r    <= '1';

      elsif rx_edge = '1' and resync_en = '1' and did_resync = '0'
            and tq_cnt /= 0 then
        -- ---------- RESYNC ----------
        if tq_cnt < END_PHASE1 then
          e := tq_cnt;              -- edge late  -> we are early
        else
          e := tq_cnt - BIT_TQ;     -- edge early -> we are late
        end if;

        if e > 0 then
          -- lengthen PHASE_SEG1 by min(e, SJW):
          -- both the bit and the sample point move out by corr
          if e > SJW then corr := SJW; else corr := e; end if;
          bit_len <= BIT_TQ + corr;
          samp_at <= END_PHASE1 - 1 + corr;
        elsif e < 0 then
          -- shorten PHASE_SEG2 by min(|e|, SJW):
          -- the bit ends early; the sample point has already passed
          if (-e) > SJW then corr := SJW; else corr := -e; end if;
          bit_len <= BIT_TQ - corr;
        end if;

        did_resync <= '1';
        tq_cnt     <= tq_cnt + 1;

      else"""

new = """      elsif rx_edge = '1' and resync_en = '1' and did_resync = '0'
            and tq_cnt /= 0 then
        -- ---------- RESYNC ----------
        -- MUST be checked BEFORE the wrap. An early-edge resync
        -- (negative phase error) arrives in PHASE_SEG2, near the
        -- end of the bit, where the wrap condition is already
        -- true. Giving the wrap priority swallowed exactly the
        -- case that PHASE_SEG2 shortening exists to handle.
        -- (Found by Check 5 returning an unmodified 16 tq bit.)
        if tq_cnt < END_PHASE1 then
          e := tq_cnt;              -- edge late  -> we are early
        else
          e := tq_cnt - BIT_TQ;     -- edge early -> we are late
        end if;

        if e > 0 then
          -- lengthen PHASE_SEG1 by min(e, SJW):
          -- both the bit and the sample point move out by corr
          if e > SJW then corr := SJW; else corr := e; end if;
          bit_len    <= BIT_TQ + corr;
          samp_at    <= END_PHASE1 - 1 + corr;
          did_resync <= '1';
          tq_cnt     <= tq_cnt + 1;

        elsif e < 0 then
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

        else
          -- e = 0, no correction
          did_resync <= '1';
          tq_cnt     <= tq_cnt + 1;
        end if;

      elsif tq_cnt >= bit_len - 1 then
        -- ---------- end of bit: wrap ----------
        tq_cnt     <= 0;
        bit_len    <= BIT_TQ;
        samp_at    <= END_PHASE1 - 1;
        did_resync <= '0';
        bitst_r    <= '1';

      else"""

assert old in s, 'RTL pattern not found - file may already be patched'
open(p, 'w').write(s.replace(old, new))
print('patched: resync now has priority over wrap')
