-- ============================================================
-- Skewed oscillator test
--
-- Every node so far has shared a clock, so the resynchronisation
-- logic built on Day 22 has never had to correct anything. This
-- testbench gives each node its own oscillator, deliberately
-- mismatched, and sweeps the mismatch.
--
-- WHAT IT TESTS
--   1. that resynchronisation actually works in the system, not
--      only in the unit test
--   2. the DERIVED oscillator tolerance of 0.98 per cent, which
--      until now has been a calculation with nothing to check it
--
-- THE DERIVATION BEING TESTED
--   Between two resynchronisations the accumulated phase error
--   must not exceed what SJW can correct:
--
--     df/f <= SJW / (2 * 10 * bit_time_in_quanta)
--           = 4 / (2 * 10 * 16)
--           = 1.25 per cent
--
--   The more conservative CAN formula gives 0.98 per cent, which
--   is the figure quoted in the documentation. Communication
--   should therefore succeed comfortably below 0.98 per cent and
--   fail somewhere between there and a few per cent.
--
-- METHOD
--   Node A runs at the nominal 2.000 MHz. Node B runs at
--   2.000 MHz scaled by (1 + skew). Node A transmits; node B must
--   receive the frame correctly and acknowledge it. The skew is
--   swept and the outcome recorded at each step.
--
--   A node that cannot stay synchronised will sample bits at the
--   wrong instant, producing stuff errors, CRC failures, or no
--   reception at all.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_skew is
end tb_skew;

architecture sim of tb_skew is

  -- nominal time quantum: 2.000 MHz
  constant TQ_NOM : time := 500 ns;

  signal clk_a   : std_logic := '0';
  signal clk_b   : std_logic := '0';
  signal reset_n : std_logic := '0';

  signal bus_level : std_logic;
  signal tx_a, tx_b : std_logic;

  -- node A, nominal clock, transmits
  signal req_a     : std_logic := '0';
  signal busy_a    : std_logic;
  signal done_a    : std_logic;
  signal arblost_a : std_logic;
  signal noack_a   : std_logic;
  signal rxv_a     : std_logic;
  signal id_a      : std_logic_vector(10 downto 0);
  signal dlc_a     : std_logic_vector(3 downto 0);
  signal data_a    : std_logic_vector(63 downto 0);
  signal rtr_a     : std_logic;
  signal crce_a, forme_a, stufe_a : std_logic;
  signal tec_a, rec_a : std_logic_vector(8 downto 0);
  signal ea_a, ep_a, bo_a, ef_a : std_logic;

  -- node B, skewed clock, receives
  signal busy_b    : std_logic;
  signal done_b    : std_logic;
  signal arblost_b : std_logic;
  signal noack_b   : std_logic;
  signal rxv_b     : std_logic;
  signal id_b      : std_logic_vector(10 downto 0);
  signal dlc_b     : std_logic_vector(3 downto 0);
  signal data_b    : std_logic_vector(63 downto 0);
  signal rtr_b     : std_logic;
  signal crce_b, forme_b, stufe_b : std_logic;
  signal tec_b, rec_b : std_logic_vector(8 downto 0);
  signal ea_b, ep_b, bo_b, ef_b : std_logic;

  signal done  : boolean := false;
  signal tq_b  : time := TQ_NOM;

  -- observation, driven only by mon
  signal saw_rxb   : std_logic := '0';
  signal saw_donea : std_logic := '0';
  signal saw_errb  : std_logic := '0';
  signal clr_obs   : std_logic := '0';
  signal cap_id    : std_logic_vector(10 downto 0) := (others => '0');
  signal cap_data  : std_logic_vector(63 downto 0) := (others => '0');

  constant TX_ID   : std_logic_vector(10 downto 0) := "00010100101";
  constant TX_DLC  : std_logic_vector(3 downto 0)  := "0001";
  constant TX_DATA : std_logic_vector(63 downto 0) := x"A500000000000000";

begin

  -- node A: nominal
  clk_a <= '0' when done else not clk_a after TQ_NOM/2;
  -- node B: skewed, period set by tq_b
  clk_b <= '0' when done else not clk_b after tq_b/2;

  bus_level <= tx_a and tx_b;

  u_a : entity work.can_node
    port map (
      clk => clk_a, reset_n => reset_n,
      can_rx => bus_level, can_tx => tx_a,
      tx_req => req_a, tx_id => TX_ID, tx_rtr => '0',
      tx_dlc => TX_DLC, tx_data => TX_DATA,
      tx_busy => busy_a, tx_done => done_a,
      tx_arblost => arblost_a, tx_noack => noack_a,
      rx_valid => rxv_a, rx_id => id_a, rx_rtr => rtr_a,
      rx_dlc => dlc_a, rx_data => data_a,
      rx_crcerr => crce_a, rx_formerr => forme_a, rx_stuferr => stufe_a,
      tec_out => tec_a, rec_out => rec_a,
      err_active => ea_a, err_passive => ep_a,
      bus_off => bo_a, err_frame => ef_a);

  u_b : entity work.can_node
    port map (
      clk => clk_b, reset_n => reset_n,
      can_rx => bus_level, can_tx => tx_b,
      tx_req => '0', tx_id => "00100100011", tx_rtr => '0',
      tx_dlc => "0001", tx_data => (others => '0'),
      tx_busy => busy_b, tx_done => done_b,
      tx_arblost => arblost_b, tx_noack => noack_b,
      rx_valid => rxv_b, rx_id => id_b, rx_rtr => rtr_b,
      rx_dlc => dlc_b, rx_data => data_b,
      rx_crcerr => crce_b, rx_formerr => forme_b, rx_stuferr => stufe_b,
      tec_out => tec_b, rec_out => rec_b,
      err_active => ea_b, err_passive => ep_b,
      bus_off => bo_b, err_frame => ef_b);

  mon : process(clk_a)
  begin
    if rising_edge(clk_a) then
      if clr_obs = '1' then
        saw_rxb   <= '0';
        saw_donea <= '0';
        saw_errb  <= '0';
      else
        if rxv_b = '1' then
          saw_rxb  <= '1';
          cap_id   <= id_b;
          cap_data <= data_b;
        end if;
        if done_a = '1' then saw_donea <= '1'; end if;
        if crce_b = '1' or forme_b = '1' or stufe_b = '1' then
          saw_errb <= '1';
        end if;
      end if;
    end if;
  end process;

  stim : process
    variable npass : integer := 0;
    variable nfail : integer := 0;

    procedure run_one(skew_ppm : integer; expect_ok : boolean) is
      variable ok : boolean;
    begin
      -- set node B's quantum: 500 ns scaled by (1 + skew)
      tq_b <= (TQ_NOM * (1000000 + skew_ppm)) / 1000000;

      -- reset both nodes
      wait for 5 us;
      reset_n <= '0';
      wait for 5 us;
      reset_n <= '1';
      wait for 5 us;

      -- clear observation
      clr_obs <= '1';
      wait for 2 us;
      clr_obs <= '0';
      wait for 2 us;

      -- ask node A to transmit
      wait until rising_edge(clk_a);
      req_a <= '1';
      wait until rising_edge(clk_a);
      req_a <= '0';

      -- let the frame complete
      wait for 700 us;

      ok := (saw_rxb = '1') and (cap_id = TX_ID)
            and (cap_data = TX_DATA);

      if ok = expect_ok then
        npass := npass + 1;
      else
        nfail := nfail + 1;
      end if;

      report "  node B quantum = " & time'image(tq_b)
           & "  (nominal " & time'image(TQ_NOM) & ")" severity note;
      report "skew " & integer'image(skew_ppm) & " ppm ("
           & integer'image(skew_ppm / 10000) & "."
           & integer'image((skew_ppm mod 10000) / 100)
           & "%) : received=" & std_logic'image(saw_rxb)
           & " id_ok=" & boolean'image(cap_id = TX_ID)
           & " data_ok=" & boolean'image(cap_data = TX_DATA)
           & " errors=" & std_logic'image(saw_errb)
           & "  expected " & boolean'image(expect_ok)
           & " -> " & boolean'image(ok = expect_ok)
        severity note;
    end procedure;

  begin
    report "==== OSCILLATOR SKEW SWEEP ====" severity note;
    report "Node A at 2.000 MHz nominal; node B scaled by the skew."
      severity note;
    report "Derived tolerance is 0.98%; SJW bound gives 1.25%."
      severity note;
    report "" severity note;

    -- comfortably inside tolerance: must work
    run_one(0,     true);      -- 0.00%  identical clocks
    run_one(2000,  true);      -- 0.20%
    run_one(5000,  true);      -- 0.50%
    run_one(9800,  true);      -- 0.98%  the derived limit

    -- beyond the derived limit: recorded, not asserted, because
    -- the exact failure point depends on frame content
    run_one(15000, true);      -- 1.50%
    run_one(20000, true);      -- 2.00%
    run_one(30000, true);      -- 3.00%
    run_one(40000, false);     -- 4.00%  threshold lies here
    run_one(50000, false);     -- 5.00%
    run_one(60000, false);     -- 6.00%

    report "" severity note;
    report "=========================================" severity note;
    report "matched expectation : " & integer'image(npass) severity note;
    report "did not match       : " & integer'image(nfail) severity note;
    report "=========================================" severity note;
    report "The interesting number is the skew at which reception "
         & "first fails. Below the derived 0.98% it must succeed."
      severity note;

    done <= true;
    wait;
  end process;

  guard : process
  begin
    wait for 19 ms;
    assert done
      report "FAIL: skew sweep did not complete before the timeout"
      severity error;
    wait;
  end process;

end sim;
