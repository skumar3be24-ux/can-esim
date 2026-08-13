-- ============================================================
-- Arbitration - Day 30, Phase 4
--
-- Three transmitting nodes start simultaneously on one wired-AND
-- bus. The node with the LOWEST identifier wins; the others must
-- detect the loss and release the bus without corrupting it.
--
--   bus = tx_A and tx_B and tx_C     (dominant '0' always wins)
--
-- FROZEN IDENTIFIERS (docs/phy_spec.md), MSB first:
--
--            id(10) ............. id(0)
--   A 0x0A5    0 0 0 1 0 1 0 0 1 0 1
--   B 0x123    0 0 1 0 0 1 0 0 0 1 1   differs at id(8)
--   C 0x2AA    0 1 0 1 0 1 0 1 0 1 0   differs at id(9)
--
--   At id(9): A sends 0, C sends 1  -> C loses first
--   At id(8): A sends 0, B sends 1  -> B loses second
--   A wins and transmits its frame to completion.
--
-- WHY THE LOSER MUST NOT CORRUPT THE BUS
--   A losing node stops transmitting and goes recessive. Since
--   recessive contributes nothing to a wired-AND, the winner's
--   frame is untouched. This is what makes CAN arbitration
--   non-destructive: no bandwidth is lost to the collision.
--
-- TESTS
--   1. A alone           -> A completes, no arbitration loss
--   2. A and B together  -> B loses, A completes
--   3. A, B and C        -> C loses first, then B, A completes
--   4. B and C together  -> C loses, B WINS (proves the winner is
--                           whoever has the lowest ID present, not
--                           a hardcoded node)
--
-- Test 4 matters: tests 2 and 3 would both pass if node A simply
-- never lost by construction.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_arb is
end tb_arb;

architecture sim of tb_arb is

  constant CLK_PERIOD : time := 500 ns;   -- 2.000 MHz

  signal clk     : std_logic := '0';
  signal reset_n : std_logic := '0';

  signal bus_level : std_logic;

  -- three nodes
  type node_sig is array (0 to 2) of std_logic;
  signal tx_out    : node_sig;
  signal start     : node_sig := (others => '0');
  signal arb_lost  : node_sig;
  signal ack_ok    : node_sig;
  signal ack_err   : node_sig;
  signal frame_act : node_sig;
  signal bslot     : node_sig;
  signal snow      : node_sig;
  signal stuffn    : node_sig;

  type id_arr is array (0 to 2) of std_logic_vector(10 downto 0);
  -- A = 0x0A5, B = 0x123, C = 0x2AA
  constant IDS : id_arr := ("00010100101", "00100100011", "01010101010");

  type fid_arr is array (0 to 2) of std_logic_vector(3 downto 0);
  signal fid : fid_arr;

  signal done : boolean := false;

  -- observation, driven only by mon
  signal saw_lost : node_sig := (others => '0');
  signal saw_done : node_sig := (others => '0');
  signal clr_obs  : std_logic := '0';

begin

  clk <= '0' when done else not clk after CLK_PERIOD/2;

  -- ============ wired-AND bus ============
  bus_level <= tx_out(0) and tx_out(1) and tx_out(2);

  -- ============ three identical nodes ============
  gen_nodes : for n in 0 to 2 generate
    u_node : entity work.can_tx_path
      port map (
        clk => clk, reset_n => reset_n,
        frame_start => start(n),
        id_in   => IDS(n),
        rtr_in  => '0',
        dlc_in  => "0001",
        data_in => (others => '0'),
        can_rx  => bus_level,
        can_tx  => tx_out(n),
        frame_active => frame_act(n),
        field_id => fid(n),
        bit_slot => bslot(n),
        sample_now => snow(n),
        stuff_now => stuffn(n),
        arb_lost => arb_lost(n),
        ack_ok => ack_ok(n),
        ack_err => ack_err(n)
      );
  end generate;

  mon : process(clk)
  begin
    if rising_edge(clk) then
      if clr_obs = '1' then
        saw_lost <= (others => '0');
        saw_done <= (others => '0');
      else
        for n in 0 to 2 loop
          if arb_lost(n) = '1' then saw_lost(n) <= '1'; end if;
          -- a node that reaches the EOF field transmitted a whole frame
          if fid(n) = x"C" then saw_done(n) <= '1'; end if;
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

    -- start the selected nodes on the SAME clock edge
    procedure contest(a, b, c : std_logic) is
    begin
      clear_obs;
      wait until falling_edge(clk);
      start(0) <= a; start(1) <= b; start(2) <= c;
      wait until falling_edge(clk);
      start <= (others => '0');
      -- let the whole frame play out
      for k in 1 to 6000 loop
        wait until falling_edge(clk);
      end loop;
    end procedure;

    procedure check(name : string;
                    exp_lost0, exp_lost1, exp_lost2 : std_logic;
                    winner : integer) is
      variable ok : boolean := true;
    begin
      if saw_lost(0) /= exp_lost0 then ok := false; end if;
      if saw_lost(1) /= exp_lost1 then ok := false; end if;
      if saw_lost(2) /= exp_lost2 then ok := false; end if;
      if saw_done(winner) /= '1'  then ok := false; end if;
      if ok then
        report "PASS " & name
             & ": lost = " & std_logic'image(saw_lost(0))
             & std_logic'image(saw_lost(1))
             & std_logic'image(saw_lost(2))
             & "  node " & integer'image(winner) & " completed"
          severity note;
      else
        nfail := nfail + 1;
        report "FAIL " & name
             & ": lost = " & std_logic'image(saw_lost(0))
             & std_logic'image(saw_lost(1))
             & std_logic'image(saw_lost(2))
             & " expected " & std_logic'image(exp_lost0)
             & std_logic'image(exp_lost1)
             & std_logic'image(exp_lost2)
             & "  reachedEOF = " & std_logic'image(saw_done(0))
             & std_logic'image(saw_done(1))
             & std_logic'image(saw_done(2))
          severity error;
      end if;
    end procedure;

  begin
    reset_n <= '0';
    wait until falling_edge(clk);
    wait until falling_edge(clk);
    reset_n <= '1';
    wait until falling_edge(clk);

    report "---- Test 1: A alone ----" severity note;
    contest('1', '0', '0');
    check("test 1 (A alone)", '0', '0', '0', 0);

    report "---- Test 2: A vs B ----" severity note;
    contest('1', '1', '0');
    check("test 2 (A vs B)", '0', '1', '0', 0);

    report "---- Test 3: A vs B vs C ----" severity note;
    contest('1', '1', '1');
    check("test 3 (A vs B vs C)", '0', '1', '1', 0);

    report "---- Test 4: B vs C, no A ----" severity note;
    contest('0', '1', '1');
    check("test 4 (B vs C)", '0', '0', '1', 1);

    report "=========================================" severity note;
    report "failures : " & integer'image(nfail) severity note;
    report "=========================================" severity note;
    if nfail = 0 then
      report "==== ARBITRATION OK ====" severity note;
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
