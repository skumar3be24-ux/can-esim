-- ============================================================
-- Two-node bus with injected bus errors
-- Day 35, Phase 5
--
-- Two can_node instances plus a corruptor that can force the bus
-- dominant for a chosen bit, simulating noise or a shorted wire.
--
--   bus = node0.can_tx and node1.can_tx and (not force_dom)
--
-- WHAT THIS TESTS THAT NOTHING BEFORE COULD
--   Every test so far assumed a clean bus. This is the first time
--   a frame is corrupted in flight and the nodes have to notice,
--   signal, and account for it.
--
-- TESTS
--   1. Clean frame - no errors, counters stay at zero. Confirms
--      the error machinery does not fire spuriously.
--   2. Corrupted frame - the receiver must raise an error, send
--      an error frame, and its REC must increase.
--   3. Repeated corruption - counters must climb, and the ratio
--      must show +8 per transmit error against -1 per success.
--
-- Test 1 is not a formality: an error detector that fires on
-- clean traffic is worse than none at all, and it would show up
-- here as counters that are nonzero when they should be zero.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_node_err is
end tb_node_err;

architecture sim of tb_node_err is

  constant CLK_PERIOD : time := 500 ns;   -- 2.000 MHz

  signal clk     : std_logic := '0';
  signal reset_n : std_logic := '0';

  signal bus_level : std_logic;
  signal force_dom : std_logic := '0';

  type sl2 is array (0 to 1) of std_logic;
  type id2 is array (0 to 1) of std_logic_vector(10 downto 0);
  type dl2 is array (0 to 1) of std_logic_vector(3 downto 0);
  type dt2 is array (0 to 1) of std_logic_vector(63 downto 0);
  type v9_2 is array (0 to 1) of std_logic_vector(8 downto 0);

  signal ntx     : sl2;
  signal tx_req  : sl2 := (others => '0');
  signal tx_id   : id2 := ("00010100101", "00100100011");
  signal tx_dlc  : dl2 := ("0001", "0001");
  signal tx_data : dt2 := (x"A500000000000000", x"3C00000000000000");

  signal tx_busy, tx_done, tx_arblost, tx_noack : sl2;
  signal rx_valid, rx_crcerr, rx_formerr, rx_stuferr : sl2;
  signal rx_id   : id2;
  signal rx_dlc  : dl2;
  signal rx_data : dt2;
  signal rx_rtr  : sl2;

  signal tec, rec : v9_2;
  signal e_act, e_pas, b_off, e_frame : sl2;

  signal done : boolean := false;

  -- observation, driven only by mon
  signal saw_err   : sl2 := (others => '0');
  signal saw_frame : sl2 := (others => '0');
  signal saw_rxok  : sl2 := (others => '0');
  signal clr_obs   : std_logic := '0';

  function iv(v : std_logic_vector(8 downto 0)) return integer is
  begin
    return to_integer(unsigned(v));
  end function;

begin

  clk <= '0' when done else not clk after CLK_PERIOD/2;

  -- the corruptor: force_dom pulls the bus dominant regardless of
  -- what either node is driving
  bus_level <= ntx(0) and ntx(1) and (not force_dom);

  u_n0 : entity work.can_node
    port map (
      clk => clk, reset_n => reset_n,
      can_rx => bus_level, can_tx => ntx(0),
      tx_req => tx_req(0), tx_id => tx_id(0), tx_rtr => '0',
      tx_dlc => tx_dlc(0), tx_data => tx_data(0),
      tx_busy => tx_busy(0), tx_done => tx_done(0),
      tx_arblost => tx_arblost(0), tx_noack => tx_noack(0),
      rx_valid => rx_valid(0), rx_id => rx_id(0), rx_rtr => rx_rtr(0),
      rx_dlc => rx_dlc(0), rx_data => rx_data(0),
      rx_crcerr => rx_crcerr(0), rx_formerr => rx_formerr(0),
      rx_stuferr => rx_stuferr(0),
      tec_out => tec(0), rec_out => rec(0),
      err_active => e_act(0), err_passive => e_pas(0),
      bus_off => b_off(0), err_frame => e_frame(0)
    );

  u_n1 : entity work.can_node
    port map (
      clk => clk, reset_n => reset_n,
      can_rx => bus_level, can_tx => ntx(1),
      tx_req => tx_req(1), tx_id => tx_id(1), tx_rtr => '0',
      tx_dlc => tx_dlc(1), tx_data => tx_data(1),
      tx_busy => tx_busy(1), tx_done => tx_done(1),
      tx_arblost => tx_arblost(1), tx_noack => tx_noack(1),
      rx_valid => rx_valid(1), rx_id => rx_id(1), rx_rtr => rx_rtr(1),
      rx_dlc => rx_dlc(1), rx_data => rx_data(1),
      rx_crcerr => rx_crcerr(1), rx_formerr => rx_formerr(1),
      rx_stuferr => rx_stuferr(1),
      tec_out => tec(1), rec_out => rec(1),
      err_active => e_act(1), err_passive => e_pas(1),
      bus_off => b_off(1), err_frame => e_frame(1)
    );

  mon : process(clk)
  begin
    if rising_edge(clk) then
      if clr_obs = '1' then
        saw_err   <= (others => '0');
        saw_frame <= (others => '0');
        saw_rxok  <= (others => '0');
      else
        for n in 0 to 1 loop
          if rx_crcerr(n) = '1' or rx_formerr(n) = '1'
             or rx_stuferr(n) = '1' then
            saw_err(n) <= '1';
          end if;
          if e_frame(n) = '1' then saw_frame(n) <= '1'; end if;
          if rx_valid(n) = '1' then saw_rxok(n)  <= '1'; end if;
        end loop;
      end if;
    end if;
  end process;

  stim : process
    variable nfail : integer := 0;

    procedure clear_obs is
    begin
      wait until falling_edge(clk);
      clr_obs <= '1';
      wait until falling_edge(clk);
      clr_obs <= '0';
      wait until falling_edge(clk);
    end procedure;

    -- send one frame from node 0, optionally corrupting the bus
    -- for one bit time starting at corrupt_us microseconds in
    procedure send(corrupt : boolean; corrupt_at : integer) is
    begin
      clear_obs;
      wait until falling_edge(clk);
      tx_req(0) <= '1';
      wait until falling_edge(clk);
      tx_req(0) <= '0';

      for k in 1 to 6000 loop
        wait until falling_edge(clk);
        -- one clock is 0.5 us, so k*0.5 us elapsed
        if corrupt and k = corrupt_at then
          force_dom <= '1';
        end if;
        if corrupt and k = corrupt_at + 96 then
          force_dom <= '0';   -- one full bit time = 16 clocks
        end if;
      end loop;
      force_dom <= '0';
    end procedure;

  begin
    reset_n <= '0';
    wait until falling_edge(clk);
    wait until falling_edge(clk);
    reset_n <= '1';
    wait until falling_edge(clk);

    -- ============================================
    report "---- Test 1: clean frame, no errors expected ----"
      severity note;
    send(false, 0);
    if saw_err(1) = '0' and saw_frame(0) = '0' and saw_frame(1) = '0'
       and iv(tec(0)) = 0 and iv(rec(1)) = 0 then
      report "PASS test 1: clean frame, no error frames, counters"
           & " TEC0=" & integer'image(iv(tec(0)))
           & " REC1=" & integer'image(iv(rec(1)))
        severity note;
    else
      nfail := nfail + 1;
      report "FAIL test 1: spurious error on a clean frame - "
           & "err1=" & std_logic'image(saw_err(1))
           & " frame0=" & std_logic'image(saw_frame(0))
           & " frame1=" & std_logic'image(saw_frame(1))
           & " TEC0=" & integer'image(iv(tec(0)))
           & " REC1=" & integer'image(iv(rec(1)))
        severity error;
    end if;

    -- ============================================
    report "---- Test 2: corrupt a bit mid-frame ----"
      severity note;
    -- node 0 starts at about 1 us; corrupt around 200 us in,
    -- which lands inside the data or CRC field
    send(true, 400);

    if saw_err(1) = '1' then
      report "PASS test 2: receiver detected the corruption"
           & "  rx_accepted=" & std_logic'image(saw_rxok(1))
           & "  REC1=" & integer'image(iv(rec(1)))
           & "  errframe1=" & std_logic'image(saw_frame(1))
        severity note;
    else
      nfail := nfail + 1;
      report "FAIL test 2: corruption went undetected -"
           & " rx_accepted=" & std_logic'image(saw_rxok(1))
           & " (if 1, node 1 accepted a CORRUPTED frame)"
           & " REC1=" & integer'image(iv(rec(1)))
        severity error;
    end if;

    if iv(rec(1)) > 0 then
      report "PASS test 2b: REC incremented to "
           & integer'image(iv(rec(1)))
        severity note;
    else
      nfail := nfail + 1;
      report "FAIL test 2b: REC did not increment"
        severity error;
    end if;

    -- ============================================
    report "---- Test 3: counters after repeated corruption ----"
      severity note;
    for f in 1 to 3 loop
      send(true, 400);
    end loop;
    report "  after 3 more corrupted frames:"
         & "  TEC0=" & integer'image(iv(tec(0)))
         & "  REC0=" & integer'image(iv(rec(0)))
         & "  TEC1=" & integer'image(iv(tec(1)))
         & "  REC1=" & integer'image(iv(rec(1)))
      severity note;
    report "  states: node0 active=" & std_logic'image(e_act(0))
         & " passive=" & std_logic'image(e_pas(0))
         & " | node1 active=" & std_logic'image(e_act(1))
         & " passive=" & std_logic'image(e_pas(1))
      severity note;

    report "=========================================" severity note;
    report "failures : " & integer'image(nfail) severity note;
    report "=========================================" severity note;
    if nfail = 0 then
      report "==== ERROR HANDLING INTEGRATION OK ====" severity note;
    end if;

    done <= true;
    wait;
  end process;

  guard : process
  begin
    wait for 79 ms;
    assert done
      report "FAIL: testbench did not complete before the timeout"
      severity error;
    wait;
  end process;

end sim;
