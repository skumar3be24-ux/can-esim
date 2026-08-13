-- ============================================================
-- Testbench for error_mgmt
-- Day 33, Phase 5
--
-- Checks the counter arithmetic, the state boundaries, and the
-- bus-off recovery sequence.
--
-- The boundary tests are the ones that matter. Off-by-one at 127
-- or 128 is the classic fault-confinement bug: a node either
-- becomes error-passive one error too early, or stays
-- error-active when it should have been muted.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_error_mgmt is
end tb_error_mgmt;

architecture sim of tb_error_mgmt is

  constant CLK_PERIOD : time := 100 ns;

  signal clk     : std_logic := '0';
  signal reset_n : std_logic := '0';

  signal tx_error   : std_logic := '0';
  signal rx_error   : std_logic := '0';
  signal rx_err_big : std_logic := '0';
  signal tx_success : std_logic := '0';
  signal rx_success : std_logic := '0';
  signal idle_11    : std_logic := '0';

  signal tec         : std_logic_vector(8 downto 0);
  signal rec         : std_logic_vector(8 downto 0);
  signal err_active  : std_logic;
  signal err_passive : std_logic;
  signal bus_off     : std_logic;

  signal done : boolean := false;

  function tecv(v : std_logic_vector(8 downto 0)) return integer is
  begin
    return to_integer(unsigned(v));
  end function;

begin

  clk <= '0' when done else not clk after CLK_PERIOD/2;

  dut : entity work.error_mgmt
    port map (
      clk => clk, reset_n => reset_n,
      tx_error => tx_error, rx_error => rx_error,
      rx_err_big => rx_err_big,
      tx_success => tx_success, rx_success => rx_success,
      idle_11 => idle_11,
      tec => tec, rec => rec,
      err_active => err_active, err_passive => err_passive,
      bus_off => bus_off
    );

  stim : process
    variable nfail : integer := 0;

    procedure pulse(signal s : out std_logic; n : integer) is
    begin
      for i in 1 to n loop
        wait until falling_edge(clk);
        s <= '1';
        wait until falling_edge(clk);
        s <= '0';
      end loop;
      wait until falling_edge(clk);
    end procedure;

    procedure check(name : string; got, want : integer) is
    begin
      if got = want then
        report "PASS " & name & " = " & integer'image(got)
          severity note;
      else
        nfail := nfail + 1;
        report "FAIL " & name & " = " & integer'image(got)
             & ", expected " & integer'image(want)
          severity error;
      end if;
    end procedure;

    procedure check_state(name : string;
                          e_act, e_pas, e_off : std_logic) is
    begin
      if err_active = e_act and err_passive = e_pas
         and bus_off = e_off then
        report "PASS " & name
             & ": active=" & std_logic'image(err_active)
             & " passive=" & std_logic'image(err_passive)
             & " busoff=" & std_logic'image(bus_off)
          severity note;
      else
        nfail := nfail + 1;
        report "FAIL " & name
             & ": active=" & std_logic'image(err_active)
             & " passive=" & std_logic'image(err_passive)
             & " busoff=" & std_logic'image(bus_off)
          severity error;
      end if;
    end procedure;

  begin
    reset_n <= '0';
    wait until falling_edge(clk);
    wait until falling_edge(clk);
    reset_n <= '1';
    wait until falling_edge(clk);

    -- ============================================
    report "---- Check 1: reset state ----" severity note;
    check("TEC after reset", tecv(tec), 0);
    check("REC after reset", tecv(rec), 0);
    check_state("state after reset", '1', '0', '0');

    -- ============================================
    report "---- Check 2: transmit error is +8 ----" severity note;
    pulse(tx_error, 1);
    check("TEC after 1 tx_error", tecv(tec), 8);

    -- ============================================
    report "---- Check 3: success is only -1 ----" severity note;
    pulse(tx_success, 1);
    check("TEC after 1 tx_success", tecv(tec), 7);
    -- seven more successes to get back to zero
    pulse(tx_success, 7);
    check("TEC after 8 successes total", tecv(tec), 0);

    -- ============================================
    report "---- Check 4: TEC does not go negative ----"
      severity note;
    pulse(tx_success, 5);
    check("TEC after extra successes", tecv(tec), 0);

    -- ============================================
    report "---- Check 5: receive error is +1 ----" severity note;
    pulse(rx_error, 3);
    check("REC after 3 rx_errors", tecv(rec), 3);
    pulse(rx_success, 1);
    check("REC after 1 rx_success", tecv(rec), 2);

    -- ============================================
    report "---- Check 6: big receive error is +8 ----"
      severity note;
    pulse(rx_err_big, 1);
    check("REC after rx_err_big", tecv(rec), 10);

    -- clear REC back to zero
    pulse(rx_success, 10);
    check("REC cleared", tecv(rec), 0);

    -- ============================================
    report "---- Check 7: error-passive boundary at 128 ----"
      severity note;
    -- 15 tx errors = 120, still active
    pulse(tx_error, 15);
    check("TEC at 15 errors", tecv(tec), 120);
    check_state("at TEC=120", '1', '0', '0');
    -- one more = 128, must flip to passive
    pulse(tx_error, 1);
    check("TEC at 16 errors", tecv(tec), 128);
    check_state("at TEC=128", '0', '1', '0');

    -- ============================================
    report "---- Check 8: bus-off boundary at 256 ----"
      severity note;
    -- 128 -> 248 is 15 more errors
    pulse(tx_error, 15);
    check("TEC before bus-off", tecv(tec), 248);
    check_state("at TEC=248", '0', '1', '0');
    -- one more = 256 -> bus off
    pulse(tx_error, 1);
    check_state("at TEC=256", '0', '0', '1');

    -- ============================================
    report "---- Check 9: bus-off ignores further errors ----"
      severity note;
    pulse(tx_error, 5);
    check_state("still bus-off", '0', '0', '1');

    -- ============================================
    report "---- Check 10: recovery after 128 idle sequences ----"
      severity note;
    pulse(idle_11, 127);
    check_state("after 127 idle sequences", '0', '0', '1');
    pulse(idle_11, 1);
    check_state("after 128 idle sequences", '1', '0', '0');
    check("TEC after recovery", tecv(tec), 0);
    check("REC after recovery", tecv(rec), 0);

    report "=========================================" severity note;
    report "failures : " & integer'image(nfail) severity note;
    report "=========================================" severity note;
    if nfail = 0 then
      report "==== ERROR MANAGEMENT OK ====" severity note;
    end if;

    done <= true;
    wait;
  end process;

  guard : process
  begin
    wait for 9 ms;
    assert done
      report "FAIL: testbench did not complete before the timeout"
      severity error;
    wait;
  end process;

end sim;
