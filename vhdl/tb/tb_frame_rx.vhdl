-- ============================================================
-- Testbench for frame_rx - receive path decode
-- Day 28, Phase 4
--
-- Feeds the STUFFED bus streams from frame_vectors.txt through
-- the verified bit_stuff receive side into frame_rx, and checks
-- the decoded ID / RTR / DLC / data against the values the
-- reference model used to build each frame.
--
--   bus stream -> [bit_stuff rx] -> [frame_rx] -> decoded fields
--                      ^                 |
--                      +--- stuff_en ----+  (combinational)
--
-- This closes the loop: Day 26-27 proved the transmitter builds
-- these exact streams, so a correct decode here means the two
-- halves agree.
--
-- WHAT IS CHECKED PER FRAME
--   rx_done pulses (frame accepted, CRC matched)
--   rx_id, rx_rtr, rx_dlc match the vector
--   rx_data matches the vector bytes
--   no crc_err, no form_err on a clean frame
--
-- PLUS two deliberate corruptions at the end:
--   a flipped data bit    -> must raise crc_err
--   a dominant EOF bit    -> must raise form_err
--
-- Day 25 timeout guard included.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_frame_rx is
end tb_frame_rx;

architecture sim of tb_frame_rx is

  constant CLK_PERIOD : time := 100 ns;

  signal clk     : std_logic := '0';
  signal reset_n : std_logic := '0';

  -- destuffer receive side
  signal rx_en       : std_logic := '0';
  signal rx_bit_in   : std_logic := '1';
  signal rx_stuff_en : std_logic;
  signal rx_bit_out  : std_logic;
  signal rx_valid    : std_logic;
  signal rx_discard  : std_logic;
  signal stuff_err   : std_logic;

  -- unused transmit side of bit_stuff
  signal tx_bit_out  : std_logic;
  signal tx_stall    : std_logic;
  signal tx_stall_c  : std_logic;

  -- decoder
  signal crc_clr : std_logic;
  signal crc_en  : std_logic;
  signal crc_bit : std_logic;
  signal crc_val : std_logic_vector(14 downto 0);

  signal dec_id   : std_logic_vector(10 downto 0);
  signal dec_rtr  : std_logic;
  signal dec_ide  : std_logic;
  signal dec_dlc  : std_logic_vector(3 downto 0);
  signal dec_data : std_logic_vector(63 downto 0);

  signal rx_active : std_logic;
  signal rx_done   : std_logic;
  signal crc_err   : std_logic;
  signal form_err  : std_logic;
  signal field_id  : std_logic_vector(3 downto 0);

  signal done : boolean := false;

  -- event latches, driven ONLY by the mon process
  signal saw_done : std_logic := '0';
  signal saw_crce : std_logic := '0';
  signal saw_form : std_logic := '0';
  signal saw_stuf : std_logic := '0';
  signal clr_flags: std_logic := '0';

begin

  clk <= '0' when done else not clk after CLK_PERIOD/2;

  u_stuff : entity work.bit_stuff
    generic map (STUFF_LEN => 5)
    port map (
      clk => clk, reset_n => reset_n,
      tx_en => '0', tx_bit_in => '1', tx_stuff_en => '0',
      tx_bit_out => tx_bit_out, tx_stall => tx_stall,
      tx_stall_c => tx_stall_c,
      rx_en => rx_en, rx_bit_in => rx_bit_in,
      rx_stuff_en => rx_stuff_en,
      rx_bit_out => rx_bit_out, rx_valid => rx_valid,
      rx_discard => rx_discard, stuff_err => stuff_err
    );

  u_dec : entity work.frame_rx
    port map (
      clk => clk, reset_n => reset_n,
      bit_valid => rx_valid, bit_in => rx_bit_out,
      bus_idle => '0',
      stuff_en => rx_stuff_en,
      crc_clr => crc_clr, crc_en => crc_en,
      crc_bit => crc_bit, crc_val => crc_val,
      rx_id => dec_id, rx_rtr => dec_rtr, rx_ide => dec_ide,
      rx_dlc => dec_dlc, rx_data => dec_data,
      rx_active => rx_active, rx_done => rx_done,
      crc_err => crc_err, form_err => form_err,
      field_id => field_id
    );

  u_crc : entity work.crc15
    port map (
      clk => clk, reset_n => reset_n,
      crc_clr => crc_clr, crc_en => crc_en,
      crc_in => crc_bit, crc_out => crc_val
    );

  -- sole driver of the event latches
  mon : process(clk)
  begin
    if rising_edge(clk) then
      if clr_flags = '1' then
        saw_done <= '0';
        saw_crce <= '0';
        saw_form <= '0';
        saw_stuf <= '0';
      else
        if rx_done  = '1' then saw_done <= '1'; end if;
        if crc_err  = '1' then saw_crce <= '1'; end if;
        if form_err = '1' then saw_form <= '1'; end if;
        if stuff_err = '1' then saw_stuf <= '1'; end if;
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

    variable expid   : std_logic_vector(10 downto 0);
    variable expdlc  : std_logic_vector(3 downto 0);
    variable expdata : std_logic_vector(63 downto 0);

    variable nframe : integer := 0;
    variable nfail  : integer := 0;

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

    -- drive one bus bit into the destuffer
    procedure feed(b : character) is
    begin
      wait until falling_edge(clk);
      if b = '1' then rx_bit_in <= '1'; else rx_bit_in <= '0'; end if;
      rx_en <= '1';
      wait until falling_edge(clk);
      rx_en <= '0';
      wait until falling_edge(clk);
    end procedure;

    procedure clear_flags is
    begin
      wait until falling_edge(clk);
      clr_flags <= '1';
      wait until falling_edge(clk);
      clr_flags <= '0';
      wait until falling_edge(clk);
    end procedure;

  begin
    file_open(status, vfile, "frame_vectors.txt", read_mode);
    assert status = open_ok
      report "FAIL: cannot open frame_vectors.txt" severity failure;

    reset_n <= '0';
    wait until falling_edge(clk);
    wait until falling_edge(clk);
    reset_n <= '1';
    wait until falling_edge(clk);

    while not endfile(vfile) and nframe < 20 loop
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

      -- expected decoded values
      expid := std_logic_vector(to_unsigned(
                 hex1(idhex(1)) * 256 + hex1(idhex(2)) * 16
                 + hex1(idhex(3)), 11));
      expdlc := std_logic_vector(to_unsigned(dlcv, 4));
      expdata := (others => '0');
      for b in 0 to (dlen / 2) - 1 loop
        expdata(63 - b*8 downto 56 - b*8) :=
          std_logic_vector(to_unsigned(
            hex1(datahex(b*2 + 1)) * 16
            + hex1(datahex(b*2 + 2)), 8));
      end loop;

      clear_flags;

      -- ---- feed the whole bus stream ----
      for k in 1 to nbus loop
        feed(ebus(k));
      end loop;
      -- a few idle bits so the decoder settles
      for k in 1 to 4 loop
        feed('1');
      end loop;

      nframe := nframe + 1;

      -- ---- check ----
      if saw_done = '0' then
        nfail := nfail + 1;
        report "FAIL frame " & integer'image(nframe)
             & ": rx_done never pulsed"
             & "  crc_err=" & std_logic'image(saw_crce)
             & "  form_err=" & std_logic'image(saw_form)
             & "  stuff_err=" & std_logic'image(saw_stuf)
             & "  field=" & integer'image(
                 to_integer(unsigned(field_id)))
          severity error;
      elsif dec_id /= expid then
        nfail := nfail + 1;
        report "FAIL frame " & integer'image(nframe)
             & ": ID mismatch" severity error;
      elsif dec_dlc /= expdlc then
        nfail := nfail + 1;
        report "FAIL frame " & integer'image(nframe)
             & ": DLC mismatch" severity error;
      elsif dec_data /= expdata then
        nfail := nfail + 1;
        report "FAIL frame " & integer'image(nframe)
             & ": data mismatch" severity error;
      else
        report "PASS frame " & integer'image(nframe)
             & ": ID/DLC/data decoded, CRC matched"
          severity note;
      end if;
    end loop;

    file_close(vfile);

    -- ============================================================
    -- ERROR INJECTION - re-read frame 1 and corrupt it three ways
    -- ============================================================
    file_open(status, vfile, "frame_vectors.txt", read_mode);
    readline(vfile, vline);
    for k in 1 to 3 loop
      read(vline, ch); idhex(k) := ch;
    end loop;
    read(vline, space); read(vline, rtrv);
    read(vline, space); read(vline, dlcv);
    read(vline, space); read(vline, ch); read(vline, space);
    read(vline, nbits); read(vline, space);
    for k in 1 to nbits loop
      read(vline, ch); ebits(k) := ch;
    end loop;
    read(vline, space);
    for k in 1 to nbits loop
      read(vline, ch); estuff(k) := ch;
    end loop;
    read(vline, space); read(vline, nbus); read(vline, space);
    for k in 1 to nbus loop
      read(vline, ch); ebus(k) := ch;
    end loop;
    file_close(vfile);

    -- ---------- A: flipped identifier bit -> CRC error ----------
    clear_flags;
    for k in 1 to nbus loop
      if k = 6 then
        -- flip a bit well inside the identifier
        if ebus(k) = '1' then feed('0'); else feed('1'); end if;
      else
        feed(ebus(k));
      end if;
    end loop;
    for k in 1 to 4 loop feed('1'); end loop;

    if saw_crce = '1' and saw_done = '0' then
      report "PASS injection A: flipped ID bit raised crc_err"
        severity note;
    else
      nfail := nfail + 1;
      report "FAIL injection A: expected crc_err only, got"
           & "  done=" & std_logic'image(saw_done)
           & "  crc_err=" & std_logic'image(saw_crce)
           & "  form_err=" & std_logic'image(saw_form)
           & "  stuff_err=" & std_logic'image(saw_stuf)
        severity error;
    end if;

    -- ---------- B: dominant bit in EOF -> form error ----------
    clear_flags;
    for k in 1 to nbus loop
      if k = nbus - 3 then
        feed('0');            -- dominant where EOF requires recessive
      else
        feed(ebus(k));
      end if;
    end loop;
    for k in 1 to 4 loop feed('1'); end loop;

    if saw_form = '1' and saw_done = '0' then
      report "PASS injection B: dominant EOF bit raised form_err"
        severity note;
    else
      nfail := nfail + 1;
      report "FAIL injection B: expected form_err only, got"
           & "  done=" & std_logic'image(saw_done)
           & "  crc_err=" & std_logic'image(saw_crce)
           & "  form_err=" & std_logic'image(saw_form)
        severity error;
    end if;

    -- ---------- C: six dominant bits -> stuff error ----------
    clear_flags;
    for k in 1 to nbus loop
      if k >= 2 and k <= 7 then
        feed('0');            -- six in a row inside the ID field
      else
        feed(ebus(k));
      end if;
    end loop;
    for k in 1 to 4 loop feed('1'); end loop;

    if saw_stuf = '1' then
      report "PASS injection C: six identical bits raised stuff_err"
        severity note;
    else
      nfail := nfail + 1;
      report "FAIL injection C: six identical bits did not raise"
           & " stuff_err" severity error;
    end if;

    report "=========================================" severity note;
    report "frames decoded : " & integer'image(nframe) severity note;
    report "failures       : " & integer'image(nfail) severity note;
    report "=========================================" severity note;

    if nfail = 0 then
      report "==== RX DECODE OK ====" severity note;
    end if;

    done <= true;
    wait;
  end process;

  guard : process
  begin
    wait for 29 ms;
    assert done
      report "FAIL: testbench did not complete before the timeout"
      severity error;
    wait;
  end process;

end sim;
