-- ============================================================
-- can_node_top wrapper check + runtime benchmark
-- Day 32
--
-- Two jobs:
--   1. Confirm the NGHDL wrapper behaves like the full can_node -
--      two instances on a bus, one transmits, the other receives
--      and acknowledges.
--   2. Measure how long 1.5 ms of simulated time takes in pure
--      GHDL, as the baseline for the NGHDL comparison.
--
-- WHY THE BENCHMARK MATTERS
--   NGHDL runs the VHDL as a socket server and does one round trip
--   per digital event. The Day 11 measurement was ONE trivial
--   instance at 4.9 s for 1.5 ms. A full can_node has far more
--   internal activity, and four of them could be 10-50x that.
--   If the mixed-signal simulation turns out to take hours, the
--   design has to be cut down - and it is far better to learn that
--   now than at Day 59.
--
--   Pure GHDL here is the floor. Whatever NGHDL costs on top is
--   the socket overhead.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_bench is
end tb_bench;

architecture sim of tb_bench is

  constant CLK_PERIOD : time := 500 ns;   -- 2.000 MHz

  signal clk     : std_logic := '0';
  signal reset_n : std_logic := '0';

  signal bus_level : std_logic;

  type sl2 is array (0 to 1) of std_logic;
  signal ntx      : sl2;
  signal tx_req   : sl2 := (others => '0');
  signal tx_busy  : sl2;
  signal tx_done  : sl2;
  signal arb_lost : sl2;
  signal rx_valid : sl2;

  type s2_2 is array (0 to 1) of std_logic_vector(1 downto 0);
  constant SEL : s2_2 := ("00", "01");   -- 0x0A5 and 0x123

  signal done : boolean := false;

  signal saw_rx : sl2 := (others => '0');
  signal saw_td : sl2 := (others => '0');
  signal saw_al : sl2 := (others => '0');

begin

  clk <= '0' when done else not clk after CLK_PERIOD/2;

  bus_level <= ntx(0) and ntx(1);

  gen : for n in 0 to 1 generate
    u : entity work.can_node_top
      port map (
        clk => clk, reset_n => reset_n,
        can_rx => bus_level, can_tx => ntx(n),
        tx_req => tx_req(n),
        id_sel => SEL(n),
        tx_busy => tx_busy(n),
        tx_done => tx_done(n),
        arb_lost => arb_lost(n),
        rx_valid => rx_valid(n)
      );
  end generate;

  mon : process(clk)
  begin
    if rising_edge(clk) then
      for n in 0 to 1 loop
        if rx_valid(n) = '1' then saw_rx(n) <= '1'; end if;
        if tx_done(n)  = '1' then saw_td(n) <= '1'; end if;
        if arb_lost(n) = '1' then saw_al(n) <= '1'; end if;
      end loop;
    end if;
  end process;

  stim : process
    variable nfail : integer := 0;
  begin
    reset_n <= '0';
    wait until falling_edge(clk);
    wait until falling_edge(clk);
    reset_n <= '1';
    wait until falling_edge(clk);

    -- ---- node 0 transmits, node 1 should receive and ACK ----
    wait until falling_edge(clk);
    tx_req(0) <= '1';
    wait until falling_edge(clk);
    tx_req(0) <= '0';

    for k in 1 to 3000 loop
      wait until falling_edge(clk);
    end loop;

    if saw_rx(1) = '1' and saw_td(0) = '1' then
      report "PASS wrapper: node 1 received, node 0 acknowledged"
        severity note;
    else
      nfail := nfail + 1;
      report "FAIL wrapper: rx1=" & std_logic'image(saw_rx(1))
           & " txdone0=" & std_logic'image(saw_td(0))
        severity error;
    end if;

    -- ---- run out to 1.5 ms of simulated time for the benchmark ----
    -- 1.5 ms / 500 ns = 3000 clocks total; keep going to reach it
    for k in 1 to 200 loop
      wait until falling_edge(clk);
    end loop;

    report "=========================================" severity note;
    report "failures : " & integer'image(nfail) severity note;
    if nfail = 0 then
      report "==== WRAPPER OK ====" severity note;
    end if;

    done <= true;
    wait;
  end process;

end sim;
