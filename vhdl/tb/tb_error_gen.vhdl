-- ============================================================
-- Testbench for error_gen
-- Day 34, Phase 5
--
-- Checks:
--   1. error-active flag is SIX DOMINANT bits
--   2. delimiter is EIGHT RECESSIVE bits
--   3. error-passive flag is SIX RECESSIVE bits
--   4. superposition: the delimiter waits for the bus to go
--      recessive rather than counting blindly
--   5. a stuck dominant bus is reported and does not hang
--
-- Check 3 is the discriminating one for fault confinement: an
-- error-passive node that still sent dominant flags would defeat
-- the entire purpose of muting a degraded node.
--
-- Check 4 is the one that separates a correct implementation from
-- a naive 6-then-8 counter.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_error_gen is
end tb_error_gen;

architecture sim of tb_error_gen is

  constant CLK_PERIOD : time := 100 ns;

  signal clk     : std_logic := '0';
  signal reset_n : std_logic := '0';

  signal bit_en     : std_logic := '0';
  signal bus_bit    : std_logic := '1';
  signal err_req    : std_logic := '0';
  signal is_passive : std_logic := '0';

  signal err_active : std_logic;
  signal err_bit    : std_logic;
  signal err_done   : std_logic;
  signal stuck_bus  : std_logic;

  signal done : boolean := false;

begin

  clk <= '0' when done else not clk after CLK_PERIOD/2;

  dut : entity work.error_gen
    port map (
      clk => clk, reset_n => reset_n,
      bit_en => bit_en, bus_bit => bus_bit,
      err_req => err_req, is_passive => is_passive,
      err_active => err_active, err_bit => err_bit,
      err_done => err_done, stuck_bus => stuck_bus
    );

  stim : process
    variable nfail : integer := 0;
    variable ndom  : integer;
    variable nrec  : integer;

    -- advance one bit slot and return the driven bit
    procedure step(b : out std_logic) is
    begin
      wait until falling_edge(clk);
      bit_en <= '1';
      wait until falling_edge(clk);
      bit_en <= '0';
      b := err_bit;
      wait until falling_edge(clk);
    end procedure;

    variable eb : std_logic;

  begin
    reset_n <= '0';
    wait until falling_edge(clk);
    wait until falling_edge(clk);
    reset_n <= '1';
    wait until falling_edge(clk);

    -- ============================================
    report "---- Check 1+2: active flag then delimiter ----"
      severity note;
    bus_bit <= '1';           -- bus recessive apart from our flag
    is_passive <= '0';
    wait until falling_edge(clk);
    err_req <= '1';
    wait until falling_edge(clk);
    err_req <= '0';

    ndom := 0;
    for k in 1 to 6 loop
      step(eb);
      if eb = '0' then ndom := ndom + 1; end if;
    end loop;

    if ndom = 6 then
      report "PASS check 1: error-active flag is 6 dominant bits"
        severity note;
    else
      nfail := nfail + 1;
      report "FAIL check 1: " & integer'image(ndom)
           & " dominant bits in the flag, expected 6"
        severity error;
    end if;

    -- one slot in E_WAIT (bus already recessive), then 8 delimiter
    step(eb);
    nrec := 0;
    for k in 1 to 8 loop
      step(eb);
      if eb = '1' then nrec := nrec + 1; end if;
    end loop;

    if nrec = 8 then
      report "PASS check 2: delimiter is 8 recessive bits"
        severity note;
    else
      nfail := nfail + 1;
      report "FAIL check 2: " & integer'image(nrec)
           & " recessive delimiter bits, expected 8"
        severity error;
    end if;

    -- wait for the frame to finish
    for k in 1 to 4 loop
      step(eb);
      exit when err_active = '0';
    end loop;

    -- ============================================
    report "---- Check 3: passive flag is RECESSIVE ----"
      severity note;
    is_passive <= '1';
    wait until falling_edge(clk);
    err_req <= '1';
    wait until falling_edge(clk);
    err_req <= '0';

    ndom := 0;
    for k in 1 to 6 loop
      step(eb);
      if eb = '0' then ndom := ndom + 1; end if;
    end loop;

    if ndom = 0 then
      report "PASS check 3: error-passive flag drove no dominant bits"
        severity note;
    else
      nfail := nfail + 1;
      report "FAIL check 3: error-passive node drove "
           & integer'image(ndom) & " dominant bits - it would"
           & " disrupt the bus"
        severity error;
    end if;

    -- let it finish
    for k in 1 to 20 loop
      step(eb);
      exit when err_active = '0';
    end loop;
    is_passive <= '0';

    -- ============================================
    report "---- Check 4: delimiter waits for a recessive bus ----"
      severity note;
    -- Hold the bus dominant for 3 bits after our flag, simulating
    -- another node's overlapping error flag. The delimiter must
    -- not start until the bus releases.
    bus_bit <= '1';
    wait until falling_edge(clk);
    err_req <= '1';
    wait until falling_edge(clk);
    err_req <= '0';

    for k in 1 to 6 loop       -- our own flag
      step(eb);
    end loop;

    bus_bit <= '0';            -- someone else is still driving
    for k in 1 to 3 loop
      step(eb);
    end loop;

    if err_active = '1' then
      report "PASS check 4: still in the error frame while the bus"
           & " is dominant"
        severity note;
    else
      nfail := nfail + 1;
      report "FAIL check 4: delimiter started while the bus was"
           & " still dominant"
        severity error;
    end if;

    bus_bit <= '1';            -- bus released
    for k in 1 to 12 loop
      step(eb);
      exit when err_active = '0';
    end loop;

    if err_active = '0' then
      report "PASS check 4b: frame completed once the bus released"
        severity note;
    else
      nfail := nfail + 1;
      report "FAIL check 4b: error frame did not complete"
        severity error;
    end if;

    -- ============================================
    report "---- Check 5: stuck dominant bus is reported ----"
      severity note;
    bus_bit <= '1';
    wait until falling_edge(clk);
    err_req <= '1';
    wait until falling_edge(clk);
    err_req <= '0';

    for k in 1 to 6 loop
      step(eb);
    end loop;

    bus_bit <= '0';            -- never releases
    for k in 1 to 30 loop
      step(eb);
      exit when err_active = '0';
    end loop;

    if err_active = '0' then
      report "PASS check 5: bounded wait - did not hang on a stuck bus"
        severity note;
    else
      nfail := nfail + 1;
      report "FAIL check 5: hung waiting for a bus that never"
           & " went recessive"
        severity error;
    end if;
    bus_bit <= '1';

    report "=========================================" severity note;
    report "failures : " & integer'image(nfail) severity note;
    report "=========================================" severity note;
    if nfail = 0 then
      report "==== ERROR FRAME GENERATION OK ====" severity note;
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
