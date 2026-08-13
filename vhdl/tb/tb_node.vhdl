-- ============================================================
-- Two-node bus - Day 31, Phase 4
--
-- Two complete can_node instances on one wired-AND bus. Each can
-- transmit and receive. This is the first test where both halves
-- of a node run together and the nodes acknowledge each other.
--
--   bus = node0.can_tx and node1.can_tx
--
-- TESTS
--   1. Node 0 sends -> node 1 receives it with the right payload,
--      node 1 ACKs, node 0 reports tx_done
--   2. Node 1 sends -> node 0 receives it. Proves both directions
--      work and that neither node is special.
--   3. Both send simultaneously -> node 0 (ID 0x0A5) wins, node 1
--      (ID 0x123) reports arbitration loss, and node 0's frame is
--      still received correctly by node 1.
--
-- Test 3 is the point of the whole day: it exercises arbitration,
-- ACK, transmit and receive together, and checks that a collision
-- does not corrupt the winner's frame.
--
-- SELF-ACK CHECK
--   A node must NOT acknowledge its own frame. If it did, tx_done
--   would fire even with the other node absent. Test 4 removes
--   node 1 and requires tx_noack.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_node is
end tb_node;

architecture sim of tb_node is

  constant CLK_PERIOD : time := 500 ns;   -- 2.000 MHz

  signal clk     : std_logic := '0';
  signal reset_n : std_logic := '0';
  signal n1_rst  : std_logic := '1';

  signal bus_level : std_logic;

  type sl2 is array (0 to 1) of std_logic;
  type id2 is array (0 to 1) of std_logic_vector(10 downto 0);
  type dl2 is array (0 to 1) of std_logic_vector(3 downto 0);
  type dt2 is array (0 to 1) of std_logic_vector(63 downto 0);

  signal ntx     : sl2;
  signal tx_req  : sl2 := (others => '0');
  signal tx_id   : id2 := ("00010100101", "00100100011");  -- 0x0A5, 0x123
  signal tx_dlc  : dl2 := ("0001", "0001");
  signal tx_data : dt2 := (x"A5000000_00000000", x"3C000000_00000000");

  signal tx_busy, tx_done, tx_arblost, tx_noack : sl2;
  signal rx_valid, rx_crcerr, rx_formerr, rx_stuferr : sl2;
  signal rx_id   : id2;
  signal rx_dlc  : dl2;
  signal rx_data : dt2;
  signal rx_rtr  : sl2;

  signal done : boolean := false;

  -- observation, driven only by mon
  signal saw_txdone, saw_arblost, saw_noack, saw_rxvalid : sl2
    := (others => '0');
  type cap2 is array (0 to 1) of std_logic_vector(63 downto 0);
  signal cap_data : cap2 := (others => (others => '0'));
  signal cap_id   : id2  := (others => (others => '0'));
  signal clr_obs  : std_logic := '0';

begin

  clk <= '0' when done else not clk after CLK_PERIOD/2;

  bus_level <= ntx(0) and ntx(1);

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
      rx_stuferr => rx_stuferr(0)
    );

  u_n1 : entity work.can_node
    port map (
      clk => clk, reset_n => n1_rst,
      can_rx => bus_level, can_tx => ntx(1),
      tx_req => tx_req(1), tx_id => tx_id(1), tx_rtr => '0',
      tx_dlc => tx_dlc(1), tx_data => tx_data(1),
      tx_busy => tx_busy(1), tx_done => tx_done(1),
      tx_arblost => tx_arblost(1), tx_noack => tx_noack(1),
      rx_valid => rx_valid(1), rx_id => rx_id(1), rx_rtr => rx_rtr(1),
      rx_dlc => rx_dlc(1), rx_data => rx_data(1),
      rx_crcerr => rx_crcerr(1), rx_formerr => rx_formerr(1),
      rx_stuferr => rx_stuferr(1)
    );

  mon : process(clk)
  begin
    if rising_edge(clk) then
      if clr_obs = '1' then
        saw_txdone  <= (others => '0');
        saw_arblost <= (others => '0');
        saw_noack   <= (others => '0');
        saw_rxvalid <= (others => '0');
      else
        for n in 0 to 1 loop
          if tx_done(n)    = '1' then saw_txdone(n)  <= '1'; end if;
          if tx_arblost(n) = '1' then saw_arblost(n) <= '1'; end if;
          if tx_noack(n)   = '1' then saw_noack(n)   <= '1'; end if;
          if rx_valid(n)   = '1' then
            saw_rxvalid(n) <= '1';
            cap_data(n) <= rx_data(n);
            cap_id(n)   <= rx_id(n);
          end if;
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

    procedure run_frames(a, b : std_logic) is
    begin
      clear_obs;
      wait until falling_edge(clk);
      tx_req(0) <= a; tx_req(1) <= b;
      wait until falling_edge(clk);
      tx_req <= (others => '0');
      for k in 1 to 6000 loop
        wait until falling_edge(clk);
      end loop;
    end procedure;

  begin
    reset_n <= '0';
    n1_rst  <= '0';
    wait until falling_edge(clk);
    wait until falling_edge(clk);
    reset_n <= '1';
    n1_rst  <= '1';
    wait until falling_edge(clk);

    -- ============ Test 1: node 0 -> node 1 ============
    report "---- Test 1: node 0 transmits ----" severity note;
    run_frames('1', '0');
    if saw_rxvalid(1) = '1' and saw_txdone(0) = '1'
       and cap_id(1) = tx_id(0)
       and cap_data(1) = tx_data(0) then
      report "PASS test 1: node 1 received ID/data, node 0 got ACK"
        severity note;
    else
      nfail := nfail + 1;
      report "FAIL test 1: rx_valid1=" & std_logic'image(saw_rxvalid(1))
           & " tx_done0=" & std_logic'image(saw_txdone(0))
           & " noack0=" & std_logic'image(saw_noack(0))
           & " crcerr1=" & std_logic'image(rx_crcerr(1))
        severity error;
    end if;

    -- ============ Test 2: node 1 -> node 0 ============
    report "---- Test 2: node 1 transmits ----" severity note;
    run_frames('0', '1');
    if saw_rxvalid(0) = '1' and saw_txdone(1) = '1'
       and cap_id(0) = tx_id(1)
       and cap_data(0) = tx_data(1) then
      report "PASS test 2: node 0 received ID/data, node 1 got ACK"
        severity note;
    else
      nfail := nfail + 1;
      report "FAIL test 2: rx_valid0=" & std_logic'image(saw_rxvalid(0))
           & " tx_done1=" & std_logic'image(saw_txdone(1))
        severity error;
    end if;

    -- ============ Test 3: collision ============
    report "---- Test 3: both transmit, node 0 must win ----"
      severity note;
    run_frames('1', '1');
    if saw_arblost(1) = '1' and saw_arblost(0) = '0'
       and saw_rxvalid(1) = '1'
       and cap_data(1) = tx_data(0) then
      report "PASS test 3: node 1 lost arbitration and still received"
           & " node 0's frame intact"
        severity note;
    else
      nfail := nfail + 1;
      report "FAIL test 3: arblost0=" & std_logic'image(saw_arblost(0))
           & " arblost1=" & std_logic'image(saw_arblost(1))
           & " rx_valid1=" & std_logic'image(saw_rxvalid(1))
           & " txdone0=" & std_logic'image(saw_txdone(0))
        severity error;
    end if;

    -- ============ Test 4: no self-ACK ============
    report "---- Test 4: node 1 absent, node 0 must see no ACK ----"
      severity note;
    n1_rst <= '0';
    run_frames('1', '0');
    if saw_noack(0) = '1' and saw_txdone(0) = '0' then
      report "PASS test 4: node 0 did not acknowledge its own frame"
        severity note;
    else
      nfail := nfail + 1;
      report "FAIL test 4: node acknowledged itself - noack0="
           & std_logic'image(saw_noack(0))
           & " txdone0=" & std_logic'image(saw_txdone(0))
        severity error;
    end if;
    n1_rst <= '1';

    report "=========================================" severity note;
    report "failures : " & integer'image(nfail) severity note;
    report "=========================================" severity note;
    if nfail = 0 then
      report "==== TWO-NODE BUS OK ====" severity note;
    end if;

    done <= true;
    wait;
  end process;

  guard : process
  begin
    wait for 39 ms;
    assert done
      report "FAIL: testbench did not complete before the timeout"
      severity error;
    wait;
  end process;

end sim;
