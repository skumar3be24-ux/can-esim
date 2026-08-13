-- ============================================================
-- Testbench for frame_gen - file-driven, bit-exact
-- Day 26, Phase 3
--
-- Reads frame_vectors.txt from tools/frame_ref.py and checks the
-- DUT emits exactly the expected bit sequence AND exactly the
-- expected stuff_en pattern, for 68 frames.
--
-- Vector format, one frame per line:
--   <id_hex> <rtr> <dlc> <datahex> <nbits> <bitstring> <stuffstring>
--
-- WHY FILE-DRIVEN AGAIN
--   Four consecutive days (22-25) the RTL was correct and my
--   hand-written expectations were wrong. Comparing against an
--   independently written model removes my expectations from the
--   loop entirely. The Python is written from ISO 11898-1, not
--   from this RTL.
--
-- WHAT IS CHECKED PER BIT
--   tx_bit   must equal the reference bit
--   stuff_en must equal the reference stuff flag
--
-- The stuff_en boundary is the point of this module: high from
-- SOF through the last CRC bit, low from the CRC delimiter
-- onward. One bit either way corrupts every frame.
--
-- Includes the Day 25 timeout guard.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_frame_gen is
end tb_frame_gen;

architecture sim of tb_frame_gen is

  constant CLK_PERIOD : time := 100 ns;

  signal clk     : std_logic := '0';
  signal reset_n : std_logic := '0';

  signal frame_start : std_logic := '0';
  signal id_in       : std_logic_vector(10 downto 0) := (others => '0');
  signal rtr_in      : std_logic := '0';
  signal dlc_in      : std_logic_vector(3 downto 0) := (others => '0');
  signal data_in     : std_logic_vector(63 downto 0) := (others => '0');

  signal bit_en       : std_logic := '0';
  signal tx_bit       : std_logic;
  signal stuff_en     : std_logic;
  signal frame_active : std_logic;

  signal crc_clr : std_logic;
  signal crc_en  : std_logic;
  signal crc_bit : std_logic;
  signal crc_val : std_logic_vector(14 downto 0);

  signal field_id : std_logic_vector(3 downto 0);

  signal done : boolean := false;

begin

  clk <= '0' when done else not clk after CLK_PERIOD/2;

  dut : entity work.frame_gen
    port map (
      clk => clk, reset_n => reset_n,
      frame_start => frame_start,
      id_in => id_in, rtr_in => rtr_in,
      dlc_in => dlc_in, data_in => data_in,
      bit_en => bit_en, tx_bit => tx_bit,
      stuff_en => stuff_en, frame_active => frame_active,
      crc_clr => crc_clr, crc_en => crc_en,
      crc_bit => crc_bit, crc_val => crc_val,
      field_id => field_id
    );

  crc : entity work.crc15
    port map (
      clk => clk, reset_n => reset_n,
      crc_clr => crc_clr, crc_en => crc_en,
      crc_in => crc_bit, crc_out => crc_val
    );

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
    variable ch      : character;
    variable space   : character;

    variable nframe    : integer := 0;
    variable nbitfail  : integer := 0;
    variable nstuffail : integer := 0;
    variable shown     : boolean := false;

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
      report "FAIL: cannot open frame_vectors.txt - run "
             & "python3 ../tools/frame_ref.py from vhdl/ first"
      severity failure;

    reset_n <= '0';
    wait until falling_edge(clk);
    wait until falling_edge(clk);
    reset_n <= '1';
    wait until falling_edge(clk);

    while not endfile(vfile) loop
      readline(vfile, vline);
      next when vline'length = 0;

      -- ---- parse the line ----
      for i in 1 to 3 loop
        read(vline, ch); idhex(i) := ch;
      end loop;
      read(vline, space);
      read(vline, rtrv);
      read(vline, space);
      read(vline, dlcv);
      read(vline, space);

      -- data bytes as hex, or '-' when there are none
      dlen := 0;
      read(vline, ch);
      if ch = '-' then
        dlen := 0;
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
      -- NOTE: when data bytes are present the loop above already
      -- consumed the trailing space via "exit when ch = ' '", so
      -- reading another space here swallows the first digit of
      -- nbits (55 parsed as 5). Only the '-' branch still needs
      -- its separator consumed.
      if dlen = 0 then
        read(vline, space);
      end if;

      read(vline, nbits);
      read(vline, space);
      for i in 1 to nbits loop
        read(vline, ch); ebits(i) := ch;
      end loop;
      read(vline, space);
      for i in 1 to nbits loop
        read(vline, ch); estuff(i) := ch;
      end loop;

      -- ---- drive the inputs ----
      id_in <= std_logic_vector(to_unsigned(
                 hex1(idhex(1)) * 256 + hex1(idhex(2)) * 16
                 + hex1(idhex(3)), 11));
      if rtrv = 1 then rtr_in <= '1'; else rtr_in <= '0'; end if;
      dlc_in <= std_logic_vector(to_unsigned(dlcv, 4));

      data_in <= (others => '0');
      for b in 0 to (dlen / 2) - 1 loop
        data_in(63 - b*8 downto 56 - b*8) <=
          std_logic_vector(to_unsigned(
            hex1(datahex(b*2 + 1)) * 16 + hex1(datahex(b*2 + 2)), 8));
      end loop;

      wait until falling_edge(clk);
      frame_start <= '1';
      wait until falling_edge(clk);
      frame_start <= '0';

      -- ---- clock out the frame, checking every bit ----
      for i in 1 to nbits loop
        wait until falling_edge(clk);
        bit_en <= '1';
        wait until falling_edge(clk);
        bit_en <= '0';
        wait until falling_edge(clk);

        if (tx_bit = '1' and ebits(i) = '0')
           or (tx_bit = '0' and ebits(i) = '1') then
          nbitfail := nbitfail + 1;
          if not shown then
            report "FIRST BIT MISMATCH frame "
                 & integer'image(nframe + 1)
                 & " bit " & integer'image(i)
                 & " expected " & ebits(i)
                 & " got " & std_logic'image(tx_bit)
                 & " field=" & integer'image(
                     to_integer(unsigned(field_id)))
              severity error;
            shown := true;
          end if;
        end if;

        if (stuff_en = '1' and estuff(i) = '0')
           or (stuff_en = '0' and estuff(i) = '1') then
          nstuffail := nstuffail + 1;
          if not shown then
            report "FIRST STUFF_EN MISMATCH frame "
                 & integer'image(nframe + 1)
                 & " bit " & integer'image(i)
                 & " expected " & estuff(i)
                 & " got " & std_logic'image(stuff_en)
                 & " field=" & integer'image(
                     to_integer(unsigned(field_id)))
              severity error;
            shown := true;
          end if;
        end if;
      end loop;

      nframe := nframe + 1;
      wait until falling_edge(clk);
    end loop;

    file_close(vfile);

    report "=========================================" severity note;
    report "frames checked      : " & integer'image(nframe)
      severity note;
    report "bit mismatches      : " & integer'image(nbitfail)
      severity note;
    report "stuff_en mismatches : " & integer'image(nstuffail)
      severity note;
    report "=========================================" severity note;

    assert nbitfail = 0
      report "FAIL: " & integer'image(nbitfail) & " bit mismatches"
      severity error;
    assert nstuffail = 0
      report "FAIL: " & integer'image(nstuffail)
             & " stuff_en mismatches"
      severity error;

    if nbitfail = 0 and nstuffail = 0 then
      report "==== ALL " & integer'image(nframe)
           & " FRAMES BIT-EXACT, STUFF BOUNDARY CORRECT ===="
        severity note;
    end if;

    done <= true;
    wait;
  end process;

  -- timeout guard (Day 25 lesson)
  guard : process
  begin
    wait for 19 ms;
    assert done
      report "FAIL: testbench did not complete before the timeout"
      severity error;
    wait;
  end process;

end sim;
