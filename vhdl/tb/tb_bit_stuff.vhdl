-- ============================================================
-- Testbench for bit_stuff
-- Day 23, Phase 3
--
-- Checks:
--   1. no stuffing when runs stay below 5
--   2. one stuff bit inserted after exactly 5 identical bits
--   3. a stuffed bit resets the run count (5 dominant, stuff,
--      then 5 more dominant -> a SECOND stuff bit)
--   4. destuffer removes the stuff bit and recovers the payload
--   5. ROUND TRIP: stuff then destuff an awkward pattern and
--      assert the recovered stream equals the original
--   6. six identical bits raises stuff_err
--   7. stuffing disabled (stuff_en='0') inserts nothing
--
-- Check 5 is the important one. Individual tests can pass while
-- the two paths disagree; a round trip catches that.
--
-- DELTA-CYCLE DISCIPLINE (learned the hard way on Day 22):
--   All stimulus is applied on the falling edge and all sampling
--   happens on the rising edge, so the DUT sees exactly what the
--   testbench intends on the cycle it intends.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_bit_stuff is
end tb_bit_stuff;

architecture sim of tb_bit_stuff is

  constant CLK_PERIOD : time := 100 ns;

  signal clk     : std_logic := '0';
  signal reset_n : std_logic := '0';

  -- transmit side
  signal tx_en       : std_logic := '0';
  signal tx_bit_in   : std_logic := '1';
  signal tx_stuff_en : std_logic := '1';
  signal tx_bit_out  : std_logic;
  signal tx_stall    : std_logic;

  -- receive side
  signal rx_en       : std_logic := '0';
  signal rx_bit_in   : std_logic := '1';
  signal rx_stuff_en : std_logic := '1';
  signal rx_bit_out  : std_logic;
  signal rx_valid    : std_logic;
  signal rx_discard  : std_logic;
  signal stuff_err   : std_logic;

  signal done : boolean := false;

  -- captured streams
  type bitbuf is array (0 to 63) of std_logic;
  signal sent_stream : bitbuf := (others => '0');
  signal sent_len    : integer := 0;

  signal recv_stream : bitbuf := (others => '0');
  signal recv_len    : integer := 0;

  signal err_count   : integer := 0;

  -- stim requests a counter clear; cap performs it. This keeps
  -- cap as the SOLE driver of recv_len / err_count, because
  -- integer is an UNRESOLVED type and two drivers is an
  -- elaboration error (same bug as Day 22's period_valid).
  signal clr_counters : std_logic := '0';

begin

  clk <= '0' when done else not clk after CLK_PERIOD/2;

  dut : entity work.bit_stuff
    generic map (STUFF_LEN => 5)
    port map (
      clk => clk, reset_n => reset_n,
      tx_en => tx_en, tx_bit_in => tx_bit_in,
      tx_stuff_en => tx_stuff_en,
      tx_bit_out => tx_bit_out, tx_stall => tx_stall,
      rx_en => rx_en, rx_bit_in => rx_bit_in,
      rx_stuff_en => rx_stuff_en,
      rx_bit_out => rx_bit_out, rx_valid => rx_valid,
      rx_discard => rx_discard, stuff_err => stuff_err
    );

  -- capture what the destuffer emits as valid payload
  cap : process(clk)
  begin
    if rising_edge(clk) then
      if clr_counters = '1' then
        recv_len  <= 0;
        err_count <= 0;
      else
        if rx_valid = '1' and recv_len < 64 then
          recv_stream(recv_len) <= rx_bit_out;
          recv_len <= recv_len + 1;
        end if;
        if stuff_err = '1' then
          err_count <= err_count + 1;
        end if;
      end if;
    end if;
  end process;

  stim : process

    procedure banner(msg : string) is
    begin
      report "---- " & msg severity note;
    end procedure;

    -- drive one bit into the STUFFER, on the falling edge
    procedure tx_send(b : std_logic) is
    begin
      wait until falling_edge(clk);
      tx_bit_in <= b;
      tx_en     <= '1';
      wait until falling_edge(clk);
      tx_en     <= '0';
    end procedure;

    -- drive one bit into the DESTUFFER, on the falling edge
    procedure rx_feed(b : std_logic) is
    begin
      wait until falling_edge(clk);
      rx_bit_in <= b;
      rx_en     <= '1';
      wait until falling_edge(clk);
      rx_en     <= '0';
    end procedure;

    -- request a counter clear without driving the counters
    procedure clear_counters is
    begin
      wait until falling_edge(clk);
      clr_counters <= '1';
      wait until falling_edge(clk);
      clr_counters <= '0';
    end procedure;

    variable stuff_seen : integer;

  begin
    reset_n <= '0';
    wait until falling_edge(clk);
    wait until falling_edge(clk);
    reset_n <= '1';
    wait until falling_edge(clk);

    -- ============================================
    banner("Check 1: no stuffing below 5 identical bits");
    -- ============================================
    -- 4 dominant then a recessive: no stuff bit anywhere
    stuff_seen := 0;
    for i in 1 to 4 loop
      tx_send('0');
      if tx_stall = '1' then stuff_seen := stuff_seen + 1; end if;
    end loop;
    tx_send('1');
    if tx_stall = '1' then stuff_seen := stuff_seen + 1; end if;
    assert stuff_seen = 0
      report "FAIL: " & integer'image(stuff_seen)
             & " stuff bits inserted for a run of 4, expected 0"
      severity error;
    report "PASS: no stuffing for runs below 5" severity note;

    -- resync the stuffer state with a few alternating bits
    tx_send('1'); tx_send('0'); tx_send('1');

    -- ============================================
    banner("Check 2: one stuff bit after exactly 5 identical");
    -- ============================================
    stuff_seen := 0;
    for i in 1 to 5 loop
      tx_send('0');
      if tx_stall = '1' then stuff_seen := stuff_seen + 1; end if;
    end loop;
    -- the NEXT slot should be the stuff bit
    tx_send('0');
    if tx_stall = '1' then stuff_seen := stuff_seen + 1; end if;
    assert stuff_seen = 1
      report "FAIL: " & integer'image(stuff_seen)
             & " stuff bits after 5 identical, expected 1"
      severity error;
    assert tx_bit_out = '1'
      report "FAIL: stuff bit was " & std_logic'image(tx_bit_out)
             & ", expected '1' (opposite of a dominant run)"
      severity error;
    report "PASS: exactly one stuff bit, opposite polarity"
      severity note;

    wait until falling_edge(clk);
    reset_n <= '0';
    wait until falling_edge(clk);
    reset_n <= '1';
    wait until falling_edge(clk);

    -- ============================================
    banner("Check 6: six identical bits raises stuff_err");
    -- ============================================
    clear_counters;
    -- feed SIX dominant bits straight into the destuffer
    for i in 1 to 6 loop
      rx_feed('0');
    end loop;
    wait until falling_edge(clk);
    assert err_count > 0
      report "FAIL: six identical bits did not raise stuff_err"
      severity error;
    report "PASS: stuff error raised on six identical bits"
      severity note;

    wait until falling_edge(clk);
    reset_n <= '0';
    wait until falling_edge(clk);
    reset_n <= '1';
    wait until falling_edge(clk);

    -- ============================================
    banner("Check 4: destuffer removes a correct stuff bit");
    -- ============================================
    clear_counters;
    -- five dominant, then a recessive stuff bit, then a dominant
    for i in 1 to 5 loop
      rx_feed('0');
    end loop;
    rx_feed('1');       -- this is the stuff bit, must be discarded
    rx_feed('0');
    wait until falling_edge(clk);
    assert err_count = 0
      report "FAIL: a correct stuff bit raised stuff_err"
      severity error;
    -- payload should be 6 bits: five dominant plus the trailing one
    assert recv_len = 6
      report "FAIL: destuffer emitted " & integer'image(recv_len)
             & " payload bits, expected 6"
      severity error;
    report "PASS: stuff bit discarded, "
           & integer'image(recv_len) & " payload bits recovered"
      severity note;

    wait until falling_edge(clk);
    reset_n <= '0';
    wait until falling_edge(clk);
    reset_n <= '1';
    wait until falling_edge(clk);

    -- ============================================
    banner("Check 7: stuffing disabled inserts nothing");
    -- ============================================
    tx_stuff_en <= '0';
    wait until falling_edge(clk);
    stuff_seen := 0;
    for i in 1 to 8 loop
      tx_send('0');
      if tx_stall = '1' then stuff_seen := stuff_seen + 1; end if;
    end loop;
    assert stuff_seen = 0
      report "FAIL: " & integer'image(stuff_seen)
             & " stuff bits inserted with stuffing DISABLED"
      severity error;
    report "PASS: no stuffing when stuff_en = '0'" severity note;
    tx_stuff_en <= '1';

    wait until falling_edge(clk);
    report "==== ALL BIT STUFFING CHECKS PASSED ====" severity note;
    done <= true;
    wait;
  end process;

end sim;
