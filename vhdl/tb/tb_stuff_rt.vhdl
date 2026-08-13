-- ============================================================
-- Bit stuffing ROUND TRIP testbench
-- Day 24, Phase 3
--
-- Day 23 verified the stuffer and destuffer in ISOLATION. That
-- cannot catch the two paths disagreeing with each other. This
-- harness wires them in series:
--
--   payload -> [stuffer] -> stuffed stream -> [destuffer] -> recovered
--
-- and asserts recovered = payload, bit for bit, for patterns
-- chosen to stress the run counter.
--
-- PATTERNS
--   A  alternating 0101...        no stuffing at all
--   B  all dominant, 12 bits      consecutive stuffing
--   C  all recessive, 12 bits     consecutive stuffing, other polarity
--   D  five dominant then five recessive then five dominant
--      -> a stuff bit at each transition boundary
--   E  a realistic CAN ID field: 0x0A5 as 11 bits
--
-- Pattern B is the important one. Twelve identical bits must
-- produce TWO stuff bits, because a stuffed bit RESETS the run
-- count to 1 - the stuffed bit is itself the first bit of the
-- next run. If the count is not reset, only one stuff bit
-- appears and the destuffer will desynchronise.
--
-- WHY tx_stall MATTERS
--   When the stuffer emits a stuff bit it asserts tx_stall,
--   meaning the payload bit offered this slot was NOT consumed.
--   The harness must re-offer that same bit next slot. Getting
--   this wrong silently drops payload bits, which is exactly the
--   bug a round trip is meant to expose.
--
-- DELTA-CYCLE DISCIPLINE (Day 22): all stimulus on the falling
-- edge, all sampling on the rising edge.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_stuff_rt is
end tb_stuff_rt;

architecture sim of tb_stuff_rt is

  constant CLK_PERIOD : time := 100 ns;
  constant MAXB       : integer := 63;

  signal clk     : std_logic := '0';
  signal reset_n : std_logic := '0';

  signal tx_en       : std_logic := '0';
  signal tx_bit_in   : std_logic := '1';
  signal tx_stuff_en : std_logic := '1';
  signal tx_bit_out  : std_logic;
  signal tx_stall    : std_logic;

  signal rx_en       : std_logic := '0';
  signal rx_bit_in   : std_logic := '1';
  signal rx_stuff_en : std_logic := '1';
  signal rx_bit_out  : std_logic;
  signal rx_valid    : std_logic;
  signal rx_discard  : std_logic;
  signal stuff_err   : std_logic;

  signal done : boolean := false;

  type bitbuf is array (0 to MAXB) of std_logic;

  -- the stuffed stream captured from the stuffer
  signal stuffed     : bitbuf := (others => '0');
  signal stuffed_len : integer := 0;
  signal cap_stuffed : std_logic := '0';   -- enable capture

  -- the payload recovered from the destuffer
  signal recov     : bitbuf := (others => '0');
  signal recov_len : integer := 0;

  signal err_count : integer := 0;
  signal clr       : std_logic := '0';
  signal tx_en_d   : std_logic := '0';   -- tx_en delayed one clock

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

  -- ---- sole driver of the stuffed stream ----
  -- tx_bit_out is REGISTERED inside the DUT: the bit produced by a
  -- tx_en pulse only appears on the NEXT clock. Capturing on the
  -- same edge as tx_en grabs the PREVIOUS slot, shifting the whole
  -- stream by one (found with the i=0 diagnostic: sent=0 stuffed=1,
  -- the reset value of tx_out_r). So delay the enable by one clock.
  cap_tx : process(clk)
  begin
    if rising_edge(clk) then
      tx_en_d <= tx_en;
      if clr = '1' then
        stuffed_len <= 0;
      elsif cap_stuffed = '1' and tx_en_d = '1' and stuffed_len <= MAXB then
        stuffed(stuffed_len) <= tx_bit_out;
        stuffed_len <= stuffed_len + 1;
      end if;
    end if;
  end process;

  -- ---- sole driver of the recovered stream ----
  cap_rx : process(clk)
  begin
    if rising_edge(clk) then
      if clr = '1' then
        recov_len <= 0;
        err_count <= 0;
      else
        if rx_valid = '1' and recov_len <= MAXB then
          recov(recov_len) <= rx_bit_out;
          recov_len <= recov_len + 1;
        end if;
        if stuff_err = '1' then
          err_count <= err_count + 1;
        end if;
      end if;
    end if;
  end process;

  stim : process

    variable pay      : bitbuf;
    variable pay_len  : integer;
    variable idx      : integer;
    variable slots    : integer;
    variable mismatch : integer;

    procedure banner(msg : string) is
    begin
      report "---- " & msg severity note;
    end procedure;

    procedure do_clr is
    begin
      wait until falling_edge(clk);
      clr <= '1';
      wait until falling_edge(clk);
      clr <= '0';
      wait until falling_edge(clk);
    end procedure;

    procedure do_reset is
    begin
      wait until falling_edge(clk);
      reset_n <= '0';
      wait until falling_edge(clk);
      wait until falling_edge(clk);
      reset_n <= '1';
      wait until falling_edge(clk);
    end procedure;

    -- ---- run one full round trip on the payload in pay/pay_len ----
    procedure round_trip(name : string) is
    begin
      do_reset;
      do_clr;

      -- ============ PHASE 1: stuff ============
      -- Offer payload bits one per slot. When tx_stall is high the
      -- bit was NOT consumed, so re-offer the same index.
      cap_stuffed <= '1';
      idx   := 0;
      slots := 0;
      while idx < pay_len and slots < MAXB loop
        wait until falling_edge(clk);
        tx_bit_in <= pay(idx);
        tx_en     <= '1';
        wait until falling_edge(clk);
        tx_en     <= '0';
        -- tx_stall is registered, so it is valid now for the slot
        -- that just completed
        if tx_stall = '0' then
          idx := idx + 1;      -- payload bit was consumed
        end if;                -- else: stuff bit sent, re-offer
        slots := slots + 1;
      end loop;

      -- drain: the stuffer may still owe a trailing stuff bit
      wait until falling_edge(clk);
      tx_bit_in <= pay(pay_len - 1);
      tx_en     <= '1';
      wait until falling_edge(clk);
      tx_en     <= '0';
      wait until falling_edge(clk);
      cap_stuffed <= '0';
      wait until falling_edge(clk);

      report name & ": " & integer'image(pay_len)
           & " payload bits -> " & integer'image(stuffed_len)
           & " stuffed bits ("
           & integer'image(stuffed_len - pay_len - 1)
           & " real stuff bits, +1 drain slot)"
        severity note;

      -- ============ PHASE 2: destuff ============
      do_reset;

      for i in 0 to stuffed_len - 2 loop   -- -2 drops the drain slot
        wait until falling_edge(clk);
        rx_bit_in <= stuffed(i);
        rx_en     <= '1';
        wait until falling_edge(clk);
        rx_en     <= '0';
      end loop;
      wait until falling_edge(clk);

      -- ============ PHASE 3: compare ============
      assert err_count = 0
        report "FAIL " & name & ": destuffer raised "
               & integer'image(err_count) & " stuff errors on a"
               & " correctly stuffed stream"
        severity error;

      assert recov_len = pay_len
        report "FAIL " & name & ": recovered "
               & integer'image(recov_len) & " bits, sent "
               & integer'image(pay_len)
        severity error;

      -- diagnostic: show both streams before comparing
      for i in 0 to pay_len - 1 loop
        report name & "  i=" & integer'image(i)
             & "  sent=" & std_logic'image(pay(i))
             & "  recv=" & std_logic'image(recov(i))
             & "  stuffed=" & std_logic'image(stuffed(i))
          severity note;
      end loop;

      mismatch := 0;
      if recov_len = pay_len then
        for i in 0 to pay_len - 1 loop
          if recov(i) /= pay(i) then
            mismatch := mismatch + 1;
          end if;
        end loop;
      end if;

      assert mismatch = 0
        report "FAIL " & name & ": " & integer'image(mismatch)
               & " bits differ after round trip"
        severity error;

      if mismatch = 0 and recov_len = pay_len then
        report "PASS " & name & ": " & integer'image(pay_len)
             & " bits recovered exactly" severity note;
      end if;
    end procedure;

  begin
    reset_n <= '0';
    wait until falling_edge(clk);
    reset_n <= '1';
    wait until falling_edge(clk);

    -- ============================================
    banner("Pattern A: alternating, no stuffing expected");
    -- ============================================
    pay_len := 12;
    for i in 0 to 11 loop
      if (i mod 2) = 0 then pay(i) := '0'; else pay(i) := '1'; end if;
    end loop;
    round_trip("A alternating");

    -- ============================================
    banner("Pattern B: 12 dominant, consecutive stuffing");
    -- ============================================
    pay_len := 12;
    for i in 0 to 11 loop pay(i) := '0'; end loop;
    round_trip("B all-dominant");

    -- ============================================
    banner("Pattern C: 12 recessive, consecutive stuffing");
    -- ============================================
    pay_len := 12;
    for i in 0 to 11 loop pay(i) := '1'; end loop;
    round_trip("C all-recessive");

    -- ============================================
    banner("Pattern D: 5 dom, 5 rec, 5 dom");
    -- ============================================
    pay_len := 15;
    for i in 0 to 4  loop pay(i) := '0'; end loop;
    for i in 5 to 9  loop pay(i) := '1'; end loop;
    for i in 10 to 14 loop pay(i) := '0'; end loop;
    round_trip("D boundaries");

    -- ============================================
    banner("Pattern E: CAN ID 0x0A5 as 11 bits");
    -- ============================================
    -- 0x0A5 = 000 1010 0101, MSB first
    pay_len := 11;
    pay(0):='0'; pay(1):='0'; pay(2):='0'; pay(3):='1';
    pay(4):='0'; pay(5):='1'; pay(6):='0'; pay(7):='0';
    pay(8):='1'; pay(9):='0'; pay(10):='1';
    round_trip("E CAN ID 0x0A5");

    wait until falling_edge(clk);
    report "==== ROUND TRIP COMPLETE ====" severity note;
    done <= true;
    wait;
  end process;

end sim;
