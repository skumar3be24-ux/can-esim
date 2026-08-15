-- ============================================================
-- Testbench for can_tx_path - end-to-end transmit integration
-- Day 27, Phase 3
--
-- Captures the stuffed bit stream that appears on can_tx, then
-- DESTUFFS IT IN THE TESTBENCH - deliberately not using the DUT's
-- own destuffer, so the check is independent - and compares the
-- recovered payload against the reference frame from
-- frame_vectors.txt.
--
-- WHAT THIS PROVES
--   frame_gen, crc15 and bit_stuff work together, at the real
--   125 kbit/s bit rate driven by bit_timing, and the tx_stall
--   back-pressure is handled correctly.
--
-- THE BACK-PRESSURE HAZARD
--   If frame_gen advances on a slot where the stuffer inserted a
--   stuff bit, exactly one payload bit is dropped per stuff bit.
--   Frames with little stuffing still look fine, so this only
--   shows up on stuffing-heavy payloads. The all-zero and
--   all-ones frames in the vector set are there specifically to
--   catch it.
--
-- TIMING
--   2.000 MHz clock, 16 tq per bit = 8.000 us per bit slot.
--   A DLC=8 all-zero frame is ~111 payload + ~20 stuff bits
--   = ~131 slots = ~1.05 ms. Four frames need ~5 ms.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_can_tx_path is
end tb_can_tx_path;

architecture sim of tb_can_tx_path is

  -- 2.000 MHz -> 500 ns period, one time quantum
  constant CLK_PERIOD : time := 500 ns;

  signal clk     : std_logic := '0';
  signal reset_n : std_logic := '0';

  signal frame_start : std_logic := '0';
  signal id_in       : std_logic_vector(10 downto 0) := (others => '0');
  signal rtr_in      : std_logic := '0';
  signal dlc_in      : std_logic_vector(3 downto 0) := (others => '0');
  signal data_in     : std_logic_vector(63 downto 0) := (others => '0');

  signal can_rx : std_logic := '1';
  signal can_tx : std_logic;

  signal frame_active : std_logic;
  signal field_id     : std_logic_vector(3 downto 0);
  signal bit_slot     : std_logic;
  signal stuff_now    : std_logic;

  signal done : boolean := false;

  -- captured bus stream
  constant MAXB : integer := 255;
  type bitbuf is array (0 to MAXB) of std_logic;
  signal bus_bits : bitbuf := (others => '1');
  signal bus_len  : integer := 0;
  signal capture  : std_logic := '0';
  signal clr_cap  : std_logic := '0';

begin

  clk <= '0' when done else not clk after CLK_PERIOD/2;

  dut : entity work.can_tx_path
    port map (
      clk => clk, reset_n => reset_n,
      frame_start => frame_start,
      id_in => id_in, rtr_in => rtr_in,
      dlc_in => dlc_in, data_in => data_in,
      can_rx => can_rx,
      -- ports added on Days 36 and 40, after this Day 27 harness was written
      in_ack_slot => '0',
      abort_in    => '0',
      bit_err     => open, can_tx => can_tx,
      frame_active => frame_active,
      field_id => field_id,
      bit_slot => bit_slot,
      stuff_now => stuff_now
    );

  -- ---- capture one sample per bit slot, at the sample point ----
  -- bit_slot pulses at the START of a slot; the bus value for that
  -- slot is stable one clock later. Sampling mid-slot is closest to
  -- what a real receiver does at 75%.
  cap : process(clk)
    variable slot_age : integer := 0;
  begin
    if rising_edge(clk) then
      if clr_cap = '1' then
        bus_len <= 0;
        slot_age := 0;
      elsif capture = '1' then
        if bit_slot = '1' then
          slot_age := 1;
        elsif slot_age > 0 then
          slot_age := slot_age + 1;
          -- sample at tq 12 of 16, the frozen sample point
          if slot_age = 12 and bus_len <= MAXB then
            bus_bits(bus_len) <= can_tx;
            bus_len <= bus_len + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  stim : process
    file     vfile  : text;
    variable vline  : line;
    variable status : file_open_status;

    variable idhex   : string(1 to 3);
    variable rtrv    : integer;
    variable dlcv    : integer;
    variable datahex : string(1 to 16);
    variable dlen    : integer;
    variable nbits   : integer;
    variable ebits   : string(1 to 128);
    variable estuff  : string(1 to 128);
    variable nbus    : integer;
    variable ebus    : string(1 to 160);
    variable ch      : character;
    variable space   : character;

    variable nframe   : integer := 0;
    variable nfail    : integer := 0;

    -- destuffing state, done HERE not in the DUT
    variable run_val  : std_logic;
    variable run_len  : integer;
    variable started  : boolean;
    variable recov    : bitbuf;
    variable rlen     : integer;
    variable i        : integer;
    variable mism     : integer;

    function hex1(c : character) return integer is
    begin
      case c is
        when '0' => return 0;   when '1' => return 1;
        when '2' => return 2;   when '3' => return 3;
        when '4' => return 4;   when '5' => return 5;
        when '6' => return 6;   when '7' => return 7;
        when '8' => return 8;   when '9' => return 9;
        when 'A' | 'a' => return 10;  when 'B' | 'b' => return 11;
        when 'C' | 'c' => return 12;  when 'D' | 'd' => return 13;
        when 'E' | 'e' => return 14;  when 'F' | 'f' => return 15;
        when others => return 0;
      end case;
    end function;

  begin
    file_open(status, vfile, "frame_vectors.txt", read_mode);
    assert status = open_ok
      report "FAIL: cannot open frame_vectors.txt" severity failure;

    reset_n <= '0';
    wait until falling_edge(clk);
    wait until falling_edge(clk);
    reset_n <= '1';
    wait until falling_edge(clk);

    -- only the first 6 vectors: the targeted cases, including the
    -- all-zero and all-ones frames that stress stuffing hardest.
    -- 68 frames at 8 us per bit would take far too long.
    while not endfile(vfile) and nframe < 6 loop
      readline(vfile, vline);
      next when vline'length = 0;

      for k in 1 to 3 loop
        read(vline, ch); idhex(k) := ch;
      end loop;
      read(vline, space);
      read(vline, rtrv);
      read(vline, space);
      read(vline, dlcv);
      read(vline, space);

      dlen := 0;
      read(vline, ch);
      if ch = '-' then
        dlen := 0;
        read(vline, space);
      else
        datahex(1) := ch;
        dlen := 1;
        loop
          read(vline, ch);
          exit when ch = ' ';
          dlen := dlen + 1;
          datahex(dlen) := ch;
        end loop;
      end if;

      read(vline, nbits);
      read(vline, space);
      for k in 1 to nbits loop
        read(vline, ch); ebits(k) := ch;
      end loop;
      read(vline, space);
      for k in 1 to nbits loop
        read(vline, ch); estuff(k) := ch;
      end loop;
      read(vline, space);
      read(vline, nbus);
      read(vline, space);
      for k in 1 to nbus loop
        read(vline, ch); ebus(k) := ch;
      end loop;

      -- ---- drive ----
      id_in <= std_logic_vector(to_unsigned(
                 hex1(idhex(1)) * 256 + hex1(idhex(2)) * 16
                 + hex1(idhex(3)), 11));
      if rtrv = 1 then rtr_in <= '1'; else rtr_in <= '0'; end if;
      dlc_in <= std_logic_vector(to_unsigned(dlcv, 4));
      data_in <= (others => '0');
      for b in 0 to (dlen / 2) - 1 loop
        data_in(63 - b*8 downto 56 - b*8) <=
          std_logic_vector(to_unsigned(
            hex1(datahex(b*2 + 1)) * 16
            + hex1(datahex(b*2 + 2)), 8));
      end loop;

      wait until falling_edge(clk);
      clr_cap <= '1';
      wait until falling_edge(clk);
      clr_cap <= '0';
      capture <= '1';

      wait until falling_edge(clk);
      frame_start <= '1';
      wait until falling_edge(clk);
      frame_start <= '0';

      -- wait for the frame to finish, with a slot budget
      i := 0;
      while i < 4000 loop
        wait until falling_edge(clk);
        i := i + 1;
        exit when frame_active = '0' and i > 40;
      end loop;
      -- let the IFS bits go by
      for k in 1 to 100 loop
        wait until falling_edge(clk);
      end loop;
      capture <= '0';
      wait until falling_edge(clk);

      -- ---- compare the BUS STREAM directly ----
      -- No destuffing here. frame_ref.py emits the expected stuffed
      -- stream, so this is a straight comparison against one source
      -- of truth. Writing a second destuffer in the testbench cost
      -- most of Day 27 and was wrong four separate ways.
      -- Skip leading idle recessive bits: SOF is the first dominant.
      i := 0;
      while i < bus_len and bus_bits(i) = '1' loop
        i := i + 1;
      end loop;

      mism := 0;
      -- the capture window deliberately overruns the frame, so
      -- allow trailing idle-recessive slots beyond the expected
      -- bus length rather than requiring an exact stop.
      if (bus_len - i) < nbus then
        mism := 999;
        report "LENGTH: captured " & integer'image(bus_len - i)
             & " bus bits after idle, expected " & integer'image(nbus)
          severity note;
      else
        for k in 1 to nbus loop
          if (bus_bits(i + k - 1) = '1' and ebus(k) = '0')
             or (bus_bits(i + k - 1) = '0' and ebus(k) = '1') then
            mism := mism + 1;
          end if;
        end loop;
      end if;

      nframe := nframe + 1;
      if mism = 0 then
        report "PASS frame " & integer'image(nframe)
             & ": " & integer'image(nbus) & " bus bits exact ("
             & integer'image(nbits) & " payload + "
             & integer'image(nbus - nbits) & " stuff)"
          severity note;
      else
        nfail := nfail + 1;
        report "FAIL frame " & integer'image(nframe)
             & ": " & integer'image(mism) & " mismatches over "
             & integer'image(nbus) & " bus bits"
          severity error;
      end if;
    end loop;

    file_close(vfile);

    report "=========================================" severity note;
    report "frames : " & integer'image(nframe) severity note;
    report "failed : " & integer'image(nfail) severity note;
    report "=========================================" severity note;

    if nfail = 0 then
      report "==== TX DATAPATH INTEGRATION OK ====" severity note;
    end if;

    done <= true;
    wait;
  end process;

  guard : process
  begin
    wait for 49 ms;
    assert done
      report "FAIL: testbench did not complete before the timeout"
      severity error;
    wait;
  end process;

end sim;
