-- ============================================================
-- Testbench for bit_timing
-- Day 22, Phase 3  (rev B)
--
-- rev A had TWO bugs, both mine:
--   1. period_valid was driven from both the period process and
--      the stim process. boolean is an UNRESOLVED type, so two
--      drivers is an elaboration error, not a runtime one.
--      Fixed: only the period process drives it.
--   2. Checks 4/5/6 waited for TWO bit_start pulses after the
--      resync edge. The FIRST pulse already ends the resynced
--      bit, so last_period at that point is the resynced value.
--      Waiting for a second read the following nominal 16 tq bit.
--      Fixed: wait for one pulse, then sample last_period.
--
-- Six checks:
--   1. free-running bit period is exactly 16 tq
--   2. sample point lands at tq index 12 (75% of the bit)
--   3. hard sync restarts the bit immediately
--   4. resync with a LATE edge lengthens PHASE_SEG1
--   5. resync with an EARLY edge shortens PHASE_SEG2
--   6. SJW caps the correction at 4 tq
--
-- Run with --assert-level=error so any failure stops the run.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_bit_timing is
end tb_bit_timing;

architecture sim of tb_bit_timing is

  constant CLK_PERIOD : time := 500 ns;   -- 2.000 MHz, one tq

  signal clk         : std_logic := '0';
  signal reset_n     : std_logic := '0';
  signal can_rx      : std_logic := '1';
  signal hard_sync   : std_logic := '0';
  signal resync_en   : std_logic := '1';

  signal tq_index    : std_logic_vector(4 downto 0);
  signal sample_pt   : std_logic;
  signal bit_start   : std_logic;
  signal sampled_bit : std_logic;
  signal seg_phase1  : std_logic;
  signal seg_phase2  : std_logic;

  signal done : boolean := false;

  -- counts tq between consecutive bit_start pulses
  -- DRIVEN ONLY BY THE period PROCESS
  signal period_cnt   : integer := 0;
  signal last_period  : integer := 0;
  signal period_valid : boolean := false;

  -- tq index at which the last sample point fired
  -- DRIVEN ONLY BY THE samprec PROCESS
  signal samp_index   : integer := -1;

begin

  clk <= '0' when done else not clk after CLK_PERIOD/2;

  dut : entity work.bit_timing
    generic map (
      SYNC_SEG   => 1,
      PROP_SEG   => 5,
      PHASE_SEG1 => 6,
      PHASE_SEG2 => 4,
      SJW        => 4
    )
    port map (
      clk         => clk,
      reset_n     => reset_n,
      can_rx      => can_rx,
      hard_sync   => hard_sync,
      resync_en   => resync_en,
      tq_index    => tq_index,
      sample_pt   => sample_pt,
      bit_start   => bit_start,
      sampled_bit => sampled_bit,
      seg_phase1  => seg_phase1,
      seg_phase2  => seg_phase2
    );

  -- ---- measure the bit period in tq ----
  period : process(clk)
  begin
    if rising_edge(clk) then
      if reset_n = '1' then
        if bit_start = '1' then
          if period_cnt > 0 then
            last_period  <= period_cnt;
            period_valid <= true;
          end if;
          period_cnt <= 1;
        else
          period_cnt <= period_cnt + 1;
        end if;
      end if;
    end if;
  end process;

  -- ---- record where the sample point fires ----
  samprec : process(clk)
  begin
    if rising_edge(clk) then
      if sample_pt = '1' then
        samp_index <= to_integer(unsigned(tq_index));
      end if;
    end if;
  end process;

  stim : process

    procedure banner(msg : string) is
    begin
      report "---- " & msg severity note;
    end procedure;

    procedure wait_tq(n : integer) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk);
      end loop;
    end procedure;

    -- inject a dominant pulse at tq index n, then wait for the
    -- resynced bit to END and return its length
    procedure resync_at(n : integer; got : out integer) is
    begin
      -- DELTA-CYCLE NOTE (real bug found with tb_probe on Day 22):
      --   "wait until rising_edge(clk) and tq_index = n" returns AT
      --   that edge. An assignment made afterwards takes effect in
      --   the NEXT delta, so the DUT does not see it until tq n+1.
      --   To make the DUT see dominant AT tq n, assign at tq n-1.
      wait until rising_edge(clk)
             and to_integer(unsigned(tq_index)) = n - 1;
      can_rx <= '0';
      wait until rising_edge(clk);
      can_rx <= '1';
      -- the NEXT bit_start ends the resynced bit
      wait until rising_edge(clk) and bit_start = '1';
      wait until rising_edge(clk);
      got := last_period;
    end procedure;

    variable got : integer;

  begin
    reset_n <= '0';
    wait_tq(3);
    reset_n <= '1';
    wait_tq(2);

    -- ============================================
    banner("Check 1: free-running bit period = 16 tq");
    -- ============================================
    wait_tq(80);
    assert period_valid
      report "FAIL: no bit_start pulses observed" severity error;
    assert last_period = 16
      report "FAIL: bit period is " & integer'image(last_period)
             & " tq, expected 16"
      severity error;
    report "PASS: bit period = " & integer'image(last_period) & " tq"
      severity note;

    -- ============================================
    banner("Check 2: sample point at tq index 12");
    -- ============================================
    assert samp_index = 12
      report "FAIL: sample point at tq " & integer'image(samp_index)
             & ", expected 12"
      severity error;
    report "PASS: sample point at tq " & integer'image(samp_index)
      severity note;

    -- ============================================
    banner("Check 3: hard sync restarts the bit");
    -- ============================================
    wait until rising_edge(clk) and to_integer(unsigned(tq_index)) = 7;
    hard_sync <= '1';
    wait until rising_edge(clk);
    hard_sync <= '0';
    wait until rising_edge(clk);
    assert to_integer(unsigned(tq_index)) = 0
      report "FAIL: after hard sync tq_index is "
             & integer'image(to_integer(unsigned(tq_index)))
             & ", expected 0"
      severity error;
    report "PASS: hard sync reset tq_index to 0" severity note;

    wait_tq(40);

    -- ============================================
    banner("Check 4: LATE edge lengthens PHASE_SEG1");
    -- ============================================
    -- edge at tq 3 -> e = +3 -> PHASE_SEG1 +3 -> bit = 19 tq
    resync_at(3, got);
    assert got = 19
      report "FAIL: after +3 resync bit was " & integer'image(got)
             & " tq, expected 19"
      severity error;
    report "PASS: +3 resync gave a " & integer'image(got) & " tq bit"
      severity note;

    wait_tq(40);

    -- ============================================
    banner("Check 5: EARLY edge shortens PHASE_SEG2");
    -- ============================================
    -- Edge SEEN at tq 14 -> e = -2. PHASE_SEG2 is truncated TO the
    -- edge, so the bit ends at index 14 = 15 quanta. It is NOT
    -- 16-2=14: the counter is already at 14 when the correction is
    -- computed, so the bit cannot end earlier than there.
    -- Shortening = 16-15 = 1 tq, within SJW=4.
    resync_at(14, got);
    assert got = 15
      report "FAIL: after -2 resync bit was " & integer'image(got)
             & " tq, expected 15 (truncate-to-edge, not 16-|e|)"
      severity error;
    report "PASS: -2 resync truncated to a " & integer'image(got) & " tq bit"
      severity note;

    wait_tq(40);

    -- ============================================
    banner("Check 6: SJW caps the correction at 4 tq");
    -- ============================================
    -- edge at tq 9 -> e = +9, capped to SJW=4 -> bit = 20 tq, NOT 25
    resync_at(9, got);
    assert got = 20
      report "FAIL: SJW cap gave a " & integer'image(got)
             & " tq bit, expected 20 (uncapped would be 25)"
      severity error;
    report "PASS: SJW capped a +9 error to +4, bit was "
           & integer'image(got) & " tq" severity note;

    wait_tq(20);

    report "==== ALL BIT TIMING CHECKS PASSED ====" severity note;
    done <= true;
    wait;
  end process;

end sim;
