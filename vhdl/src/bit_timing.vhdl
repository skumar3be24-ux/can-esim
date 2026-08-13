-- ============================================================
-- CAN bit timing logic
-- Day 22, Phase 3  (rev B)
--
-- rev A gave a 20 tq bit for a +3 resync instead of 19. The bug
-- was structural, not arithmetic: end_bit was recomputed EVERY
-- cycle from the ph1_extra / ph2_less SIGNALS, which update one
-- cycle after the edge is detected. The wrap comparison therefore
-- saw a moving target and the correction was effectively applied
-- one cycle late.
--
-- rev B fixes it by computing the bit length ONCE, at the moment
-- of resync, into a single registered signal bit_len. Nothing
-- recomputes it afterwards, so there is no moving target and the
-- off-by-one class of bug is removed entirely.
--
-- FROZEN PARAMETERS (docs/phy_spec.md):
--   clock      2.000 MHz  -> one tq per clock cycle, tq = 500 ns
--   bit time   16 tq = 8.000 us  -> 125 kbit/s
--   SYNC_SEG    1 tq   (tq index 0)
--   PROP_SEG    5 tq   (tq index 1..5)
--   PHASE_SEG1  6 tq   (tq index 6..11)
--   PHASE_SEG2  4 tq   (tq index 12..15)
--   sample point after tq index 11
--   SJW         4 tq
--
-- SEGMENT LAYOUT, tq index 0..15:
--
--   0        1  2  3  4  5     6  7  8  9 10 11    12 13 14 15
--  |SYNC|      PROP_SEG      |    PHASE_SEG1    |  PHASE_SEG2  |
--                                              ^
--                                    sample point (after tq 11)
--
-- SYNCHRONISATION
--
--  HARD SYNC - on SOF only. Restarts the bit unconditionally.
--
--  RESYNC - on any recessive->dominant edge outside hard sync.
--    Phase error e is the edge position relative to SYNC_SEG:
--       e = tq_index                    if edge in PROP/PHASE1
--       e = tq_index - BIT_TQ           if edge in PHASE2
--    e > 0 : we are EARLY -> lengthen PHASE_SEG1 by min(e, SJW)
--    e < 0 : we are LATE  -> shorten  PHASE_SEG2 by min(|e|, SJW)
--
--    SJW caps the per-bit correction. That cap is what bounds the
--    tolerable oscillator mismatch to 0.98%.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bit_timing is
  generic (
    SYNC_SEG   : integer := 1;
    PROP_SEG   : integer := 5;
    PHASE_SEG1 : integer := 6;
    PHASE_SEG2 : integer := 4;
    SJW        : integer := 4
  );
  port (
    clk        : in  std_logic;   -- 2.000 MHz, one tq per cycle
    reset_n    : in  std_logic;   -- async active-low

    can_rx     : in  std_logic;   -- synchronised bus level
    hard_sync  : in  std_logic;   -- pulse to force a hard sync (SOF)
    resync_en  : in  std_logic;   -- allow resynchronisation

    tq_index   : out std_logic_vector(4 downto 0);  -- 0..~20
    sample_pt  : out std_logic;   -- one-cycle pulse at the sample point
    bit_start  : out std_logic;   -- one-cycle pulse at the start of a bit
    sampled_bit: out std_logic;   -- bus level latched at the sample point
    seg_phase1 : out std_logic;   -- high during PHASE_SEG1
    seg_phase2 : out std_logic    -- high during PHASE_SEG2
  );
end bit_timing;

architecture rtl of bit_timing is

  -- nominal boundaries as tq indices
  constant END_SYNC   : integer := SYNC_SEG;                          -- 1
  constant END_PROP   : integer := SYNC_SEG + PROP_SEG;               -- 6
  constant END_PHASE1 : integer := SYNC_SEG + PROP_SEG + PHASE_SEG1;  -- 12
  constant BIT_TQ     : integer := SYNC_SEG + PROP_SEG
                                 + PHASE_SEG1 + PHASE_SEG2;           -- 16

  signal tq_cnt : integer range 0 to 31 := 0;

  -- THE key change from rev A: both of these are computed once,
  -- at reset / wrap / resync, and never recomputed in between.
  --   bit_len  = total quanta in the CURRENT bit
  --   samp_at  = tq index whose completion triggers the sample point
  signal bit_len : integer range 1 to 31 := BIT_TQ;
  signal samp_at : integer range 0 to 31 := END_PHASE1 - 1;

  -- edge detection on the bus
  signal rx_prev : std_logic := '1';
  signal rx_edge : std_logic;   -- recessive -> dominant this cycle

  signal did_resync : std_logic := '0';   -- one resync per bit

  signal samp_r  : std_logic := '0';
  signal bitst_r : std_logic := '0';
  signal sbit_r  : std_logic := '1';

begin

  rx_edge <= '1' when (rx_prev = '1' and can_rx = '0') else '0';

  process(clk, reset_n)
    variable e    : integer range -31 to 31;
    variable corr : integer range 0 to 31;
  begin
    if reset_n = '0' then
      tq_cnt     <= 0;
      bit_len    <= BIT_TQ;
      samp_at    <= END_PHASE1 - 1;
      rx_prev    <= '1';
      did_resync <= '0';
      samp_r     <= '0';
      bitst_r    <= '0';
      sbit_r     <= '1';

    elsif rising_edge(clk) then
      rx_prev <= can_rx;
      samp_r  <= '0';
      bitst_r <= '0';

      -- ---------- sample point ----------
      -- evaluated against the CURRENT samp_at, which only ever
      -- changes at a resync that happens before this point
      if tq_cnt = samp_at and hard_sync = '0' then
        samp_r <= '1';
        sbit_r <= can_rx;
      end if;

      if hard_sync = '1' then
        -- ---------- HARD SYNC: restart the bit now ----------
        tq_cnt     <= 0;
        bit_len    <= BIT_TQ;
        samp_at    <= END_PHASE1 - 1;
        did_resync <= '0';
        bitst_r    <= '1';

      elsif rx_edge = '1' and resync_en = '1' and did_resync = '0'
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

      else
        tq_cnt <= tq_cnt + 1;
      end if;

    end if;
  end process;

  tq_index    <= std_logic_vector(to_unsigned(tq_cnt, 5));
  sample_pt   <= samp_r;
  bit_start   <= bitst_r;
  sampled_bit <= sbit_r;

  seg_phase1 <= '1' when (tq_cnt >= END_PROP and tq_cnt <= samp_at) else '0';
  seg_phase2 <= '1' when (tq_cnt >  samp_at) else '0';

end rtl;
