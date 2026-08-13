-- ============================================================
-- Diagnostic probe for bit_timing
-- Prints tq_index, bit_start, rx and the measured period on every
-- clock so the +3 resync can be traced cycle by cycle.
--
-- This is a THROWAWAY debug harness, not a test. It asserts
-- nothing. Its only job is to show what actually happens around
-- the resync so the 19-vs-20 discrepancy can be located instead
-- of guessed at.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_probe is
end tb_probe;

architecture sim of tb_probe is

  constant CLK_PERIOD : time := 500 ns;

  signal clk       : std_logic := '0';
  signal reset_n   : std_logic := '0';
  signal can_rx    : std_logic := '1';
  signal hard_sync : std_logic := '0';
  signal resync_en : std_logic := '1';

  signal tq_index    : std_logic_vector(4 downto 0);
  signal sample_pt   : std_logic;
  signal bit_start   : std_logic;
  signal sampled_bit : std_logic;
  signal seg_phase1  : std_logic;
  signal seg_phase2  : std_logic;

  signal done    : boolean := false;
  signal tracing : boolean := false;

begin

  clk <= '0' when done else not clk after CLK_PERIOD/2;

  dut : entity work.bit_timing
    generic map (
      SYNC_SEG => 1, PROP_SEG => 5, PHASE_SEG1 => 6,
      PHASE_SEG2 => 4, SJW => 4
    )
    port map (
      clk => clk, reset_n => reset_n, can_rx => can_rx,
      hard_sync => hard_sync, resync_en => resync_en,
      tq_index => tq_index, sample_pt => sample_pt,
      bit_start => bit_start, sampled_bit => sampled_bit,
      seg_phase1 => seg_phase1, seg_phase2 => seg_phase2
    );

  -- ---- print every cycle while tracing ----
  trace : process(clk)
    variable cyc : integer := 0;
  begin
    if rising_edge(clk) then
      if tracing then
        cyc := cyc + 1;
        report "cyc=" & integer'image(cyc)
             & "  tq=" & integer'image(to_integer(unsigned(tq_index)))
             & "  bit_start=" & std_logic'image(bit_start)
             & "  sample=" & std_logic'image(sample_pt)
             & "  rx=" & std_logic'image(can_rx)
          severity note;
      end if;
    end if;
  end process;

  stim : process
    procedure wait_tq(n : integer) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk);
      end loop;
    end procedure;
  begin
    reset_n <= '0';
    wait_tq(3);
    reset_n <= '1';

    -- settle into free running
    wait_tq(40);

    -- start tracing at a known bit boundary
    wait until rising_edge(clk) and bit_start = '1';
    tracing <= true;
    report "==== TRACE START: free-running bit ====" severity note;

    -- one full clean bit for reference
    wait until rising_edge(clk) and bit_start = '1';
    report "==== next bit: inject dominant at tq 13 -> DUT sees tq 14 ====" severity note;

    -- now inject the +3 resync
    wait until rising_edge(clk) and to_integer(unsigned(tq_index)) = 13;
    can_rx <= '0';
    wait until rising_edge(clk);
    can_rx <= '1';

    -- watch the resynced bit end
    wait until rising_edge(clk) and bit_start = '1';
    report "==== resynced bit ended here ====" severity note;

    -- one more clean bit
    wait until rising_edge(clk) and bit_start = '1';
    report "==== TRACE END ====" severity note;

    tracing <= false;
    wait_tq(2);
    done <= true;
    wait;
  end process;

end sim;
