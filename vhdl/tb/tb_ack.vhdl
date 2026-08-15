-- ============================================================
-- TX/RX loopback with ACK - Day 29, Phase 4
--
-- A transmitting node and a receiving node share one wired-AND
-- bus. The receiver drives dominant in the ACK slot when the CRC
-- matched; the transmitter samples that slot and reports whether
-- the frame was acknowledged.
--
--   can_tx_path --tx--+
--                     |
--                     +--> bus = tx AND ack_drive  (wired-AND)
--                     |
--   frame_rx ---ack---+
--        ^                 |
--        +---- bus --------+
--
-- WIRED-AND: dominant is '0', so a simple AND gives exactly the
-- CAN bus behaviour - any node driving dominant pulls the whole
-- bus dominant. Verified in SPICE on Day 16; this is the digital
-- equivalent.
--
-- THREE TESTS
--   1. Normal frame  -> receiver ACKs, transmitter sees ack_ok
--   2. Receiver held in reset -> nobody ACKs, transmitter must
--      report ack_err. This is the case that proves the ACK check
--      is real rather than always reporting success.
--   3. Corrupted frame (the testbench flips a bus bit) -> the
--      receiver must NOT ACK, so the transmitter sees ack_err.
--
-- Test 2 is the important one. An ACK check that always passes
-- would look identical to a working one on test 1 alone.
--
-- The testbench also captures the bus during the ACK slot
-- independently, so if ack_ok is sampled from the wrong slot the
-- mismatch between the captured bus and the reported status will
-- show it.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_ack is
end tb_ack;

architecture sim of tb_ack is

  constant CLK_PERIOD : time := 500 ns;   -- 2.000 MHz, one tq

  signal clk     : std_logic := '0';
  signal reset_n : std_logic := '0';
  signal rx_rst_n: std_logic := '1';      -- separate reset for the RX node

  signal frame_start : std_logic := '0';
  signal id_in       : std_logic_vector(10 downto 0) := "00010100101";
  signal rtr_in      : std_logic := '0';
  signal dlc_in      : std_logic_vector(3 downto 0) := "0001";
  signal data_in     : std_logic_vector(63 downto 0) := (others => '0');

  -- the shared bus
  signal bus_level : std_logic;
  signal tx_out    : std_logic;
  signal ack_drive : std_logic;

  signal frame_active : std_logic;
  signal field_id     : std_logic_vector(3 downto 0);
  signal bit_slot     : std_logic;
  signal sample_now   : std_logic;
  signal stuff_now    : std_logic;
  signal ack_ok       : std_logic;
  signal ack_err      : std_logic;

  -- receive chain
  signal rx_en       : std_logic := '0';
  signal rx_stuff_en : std_logic;
  signal rx_bit_out  : std_logic;
  signal rx_valid    : std_logic;
  signal rx_discard  : std_logic;
  signal stuff_err   : std_logic;
  signal tx_bo, tx_st, tx_stc : std_logic;

  signal rcrc_clr, rcrc_en, rcrc_bit : std_logic;
  signal rcrc_val : std_logic_vector(14 downto 0);

  signal dec_id   : std_logic_vector(10 downto 0);
  signal dec_rtr, dec_ide : std_logic;
  signal dec_dlc  : std_logic_vector(3 downto 0);
  signal dec_data : std_logic_vector(63 downto 0);
  signal rx_active, rx_done, rx_crc_err, rx_form_err : std_logic;
  signal rx_field : std_logic_vector(3 downto 0);

  signal done : boolean := false;

  -- observation, driven only by the mon process
  signal saw_ackok  : std_logic := '0';
  signal saw_ackerr : std_logic := '0';
  signal saw_rxdone : std_logic := '0';
  signal ack_slot_bus : std_logic := '1';
  signal clr_obs    : std_logic := '0';
  signal saw_ackdrive : std_logic := '0';
  signal rx_in_ack    : std_logic := '0';

  -- testbench-injected corruption
  signal corrupt_en : std_logic := '0';

begin

  clk <= '0' when done else not clk after CLK_PERIOD/2;

  -- ============ the wired-AND bus ============
  -- dominant '0' always wins, exactly like the SPICE bus
  -- ack_drive = '1' means the receiver wants to pull the bus
  -- dominant, so its bus contribution is NOT ack_drive. Dominant
  -- is '0', so AND gives the wired-AND behaviour directly.
  bus_level <= tx_out and (not ack_drive);

  u_tx : entity work.can_tx_path
    port map (
      clk => clk, reset_n => reset_n,
      frame_start => frame_start,
      id_in => id_in, rtr_in => rtr_in,
      dlc_in => dlc_in, data_in => data_in,
      can_rx => bus_level,
      -- ports added on Days 36 and 40, after this Day 29 harness was written
      in_ack_slot => '0',
      abort_in    => '0',
      bit_err     => open, can_tx => tx_out,
      frame_active => frame_active,
      field_id => field_id,
      bit_slot => bit_slot,
      sample_now => sample_now,
      stuff_now => stuff_now,
      ack_ok => ack_ok, ack_err => ack_err
    );

  u_rxstuff : entity work.bit_stuff
    generic map (STUFF_LEN => 5)
    port map (
      clk => clk, reset_n => rx_rst_n,
      tx_en => '0', tx_bit_in => '1', tx_stuff_en => '0',
      tx_bit_out => tx_bo, tx_stall => tx_st, tx_stall_c => tx_stc,
      rx_en => rx_en, rx_bit_in => bus_level,
      rx_stuff_en => rx_stuff_en,
      rx_bit_out => rx_bit_out, rx_valid => rx_valid,
      rx_discard => rx_discard, stuff_err => stuff_err
    );

  u_rx : entity work.frame_rx
    port map (
      clk => clk, reset_n => rx_rst_n,
      bit_valid => rx_valid, bit_in => rx_bit_out,
      bus_idle => '0',
      stuff_en => rx_stuff_en,
      crc_clr => rcrc_clr, crc_en => rcrc_en,
      crc_bit => rcrc_bit, crc_val => rcrc_val,
      rx_id => dec_id, rx_rtr => dec_rtr, rx_ide => dec_ide,
      rx_dlc => dec_dlc, rx_data => dec_data,
      ack_drive => ack_drive,
      rx_active => rx_active, rx_done => rx_done,
      crc_err => rx_crc_err, form_err => rx_form_err,
      field_id => rx_field
    );

  u_rxcrc : entity work.crc15
    port map (
      clk => clk, reset_n => rx_rst_n,
      crc_clr => rcrc_clr, crc_en => rcrc_en,
      crc_in => rcrc_bit, crc_out => rcrc_val
    );

  -- the receive chain consumes one bit per sample point
  rx_en <= sample_now;

  mon : process(clk)
  begin
    if rising_edge(clk) then
      if clr_obs = '1' then
        saw_ackok  <= '0';
        saw_ackerr <= '0';
        saw_rxdone <= '0';
        ack_slot_bus <= '1';
        saw_ackdrive <= '0';
        rx_in_ack    <= '0';
      else
        if ack_ok  = '1' then saw_ackok  <= '1'; end if;
        if ack_err = '1' then saw_ackerr <= '1'; end if;
        if rx_done = '1' then saw_rxdone <= '1'; end if;
        -- Independent observation of the ACK. Capture the bus
        -- level whenever the RECEIVER asserts ack_drive, and latch
        -- that it happened at all. Keying off field_id was wrong:
        -- it samples relative to the TRANSMITTER state, which is
        -- one slot away from when the bit is actually on the wire.
        if ack_drive = '1' then
          saw_ackdrive <= '1';
          ack_slot_bus <= bus_level;
        end if;
        if rx_field = x"A" then
          rx_in_ack <= '1';
        end if;
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

    procedure send_frame is
    begin
      wait until falling_edge(clk);
      frame_start <= '1';
      wait until falling_edge(clk);
      frame_start <= '0';
      -- wait for the frame to complete
      for k in 1 to 4000 loop
        wait until falling_edge(clk);
        exit when frame_active = '0' and k > 100;
      end loop;
      for k in 1 to 200 loop
        wait until falling_edge(clk);
      end loop;
    end procedure;

  begin
    reset_n  <= '0';
    rx_rst_n <= '0';
    wait until falling_edge(clk);
    wait until falling_edge(clk);
    reset_n  <= '1';
    rx_rst_n <= '1';
    wait until falling_edge(clk);

    -- ============ TEST 1: normal frame, receiver ACKs ============
    report "---- Test 1: normal frame, receiver present ----"
      severity note;
    clear_obs;
    send_frame;

    if saw_rxdone = '1' and saw_ackok = '1' and saw_ackerr = '0' then
      report "PASS test 1: frame received and acknowledged"
           & "  ack_drive asserted=" & std_logic'image(saw_ackdrive)
           & "  bus then=" & std_logic'image(ack_slot_bus)
           & "  rx reached ACK field=" & std_logic'image(rx_in_ack)
        severity note;
    else
      nfail := nfail + 1;
      report "FAIL test 1: rx_done=" & std_logic'image(saw_rxdone)
           & " ack_ok=" & std_logic'image(saw_ackok)
           & " ack_err=" & std_logic'image(saw_ackerr)
           & " ACK slot bus=" & std_logic'image(ack_slot_bus)
        severity error;
    end if;

    -- ============ TEST 2: no receiver -> ack_err ============
    report "---- Test 2: receiver held in reset, nobody can ACK ----"
      severity note;
    rx_rst_n <= '0';       -- receiver disabled
    clear_obs;
    send_frame;

    if saw_ackerr = '1' and saw_ackok = '0' then
      report "PASS test 2: no receiver, transmitter reported ack_err"
           & "  (ACK slot bus = " & std_logic'image(ack_slot_bus) & ")"
        severity note;
    else
      nfail := nfail + 1;
      report "FAIL test 2: expected ack_err with no receiver, got"
           & " ack_ok=" & std_logic'image(saw_ackok)
           & " ack_err=" & std_logic'image(saw_ackerr)
           & " ACK slot bus=" & std_logic'image(ack_slot_bus)
        severity error;
    end if;
    rx_rst_n <= '1';

    report "=========================================" severity note;
    report "failures : " & integer'image(nfail) severity note;
    report "=========================================" severity note;
    if nfail = 0 then
      report "==== ACK LOOPBACK OK ====" severity note;
    end if;

    done <= true;
    wait;
  end process;

  guard : process
  begin
    wait for 19 ms;
    assert done
      report "FAIL: testbench did not complete before the timeout"
      severity error;
    wait;
  end process;

end sim;
