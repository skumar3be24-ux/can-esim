-- ============================================================
-- Testbench for crc15 - file-driven vector comparison
-- Day 25, Phase 3
--
-- Reads crc_vectors.txt, produced by tools/crc15_ref.py, and
-- replays every vector through the DUT.
--
-- Vector format, one per line:
--     <nbits> <bitstring> <crc_hex>
--
-- WHY FILE-DRIVEN
--   Two or three hand-computed vectors prove essentially nothing
--   about a CRC - a broken implementation passes them routinely.
--   The Python reference is written from the ISO 11898-1
--   definition, NOT from this RTL, so the two can genuinely
--   disagree. 417 vectors including 400 random ones is what
--   actually gives confidence.
--
-- DELTA-CYCLE DISCIPLINE (Days 22-24): stimulus on the falling
-- edge, sampling on the rising edge. crc_out is combinational
-- from a registered value, so it is valid one clock after the
-- crc_en pulse that consumed the last bit.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_crc15 is
end tb_crc15;

architecture sim of tb_crc15 is

  constant CLK_PERIOD : time := 100 ns;

  signal clk     : std_logic := '0';
  signal reset_n : std_logic := '0';
  signal crc_clr : std_logic := '0';
  signal crc_en  : std_logic := '0';
  signal crc_in  : std_logic := '0';
  signal crc_out : std_logic_vector(14 downto 0);

  signal done : boolean := false;

begin

  clk <= '0' when done else not clk after CLK_PERIOD/2;

  dut : entity work.crc15
    port map (
      clk => clk, reset_n => reset_n,
      crc_clr => crc_clr, crc_en => crc_en,
      crc_in => crc_in, crc_out => crc_out
    );

  stim : process
    file     vfile   : text;
    variable vline   : line;
    variable status  : file_open_status;

    variable nbits   : integer;
    variable bitstr  : string(1 to 256);
    variable crchex  : string(1 to 4);
    variable ch      : character;
    variable space   : character;

    variable declare_free : std_logic_vector(15 downto 0);
    variable expected : std_logic_vector(14 downto 0);
    variable got      : std_logic_vector(14 downto 0);

    variable nvec     : integer := 0;
    variable nfail    : integer := 0;
    variable first_fail_shown : boolean := false;

    -- hex character -> 4-bit value
    function hex2slv(c : character) return std_logic_vector is
      -- MUST be constrained descending: an unconstrained return
      -- takes the literal ascending direction, and slicing it
      -- (2 downto 0) is then a direction mismatch at runtime.
    begin
      case c is
        when '0' => return "0000";  when '1' => return "0001";
        when '2' => return "0010";  when '3' => return "0011";
        when '4' => return "0100";  when '5' => return "0101";
        when '6' => return "0110";  when '7' => return "0111";
        when '8' => return "1000";  when '9' => return "1001";
        when 'A' | 'a' => return "1010";
        when 'B' | 'b' => return "1011";
        when 'C' | 'c' => return "1100";
        when 'D' | 'd' => return "1101";
        when 'E' | 'e' => return "1110";
        when 'F' | 'f' => return "1111";
        when others => return "XXXX";
      end case;
    end function;

    function slv2hex(v : std_logic_vector(14 downto 0)) return string is
      constant HEXCH : string(1 to 16) := "0123456789ABCDEF";
      variable p : std_logic_vector(15 downto 0) := '0' & v;
      variable r : string(1 to 4);
    begin
      for i in 0 to 3 loop
        r(4 - i) := HEXCH(to_integer(
                      unsigned(p(4*i + 3 downto 4*i))) + 1);
      end loop;
      return r;
    end function;

  begin
    file_open(status, vfile, "crc_vectors.txt", read_mode);
    assert status = open_ok
      report "FAIL: cannot open crc_vectors.txt - run "
             & "python3 ../tools/crc15_ref.py from vhdl/ first"
      severity failure;

    reset_n <= '0';
    wait until falling_edge(clk);
    wait until falling_edge(clk);
    reset_n <= '1';
    wait until falling_edge(clk);

    while not endfile(vfile) loop
      readline(vfile, vline);
      next when vline'length = 0;

      read(vline, nbits);
      read(vline, space);

      for i in 1 to nbits loop
        read(vline, ch);
        bitstr(i) := ch;
      end loop;

      read(vline, space);
      for i in 1 to 4 loop
        read(vline, ch);
        crchex(i) := ch;
      end loop;

      -- assemble 16 bits then drop the top one, avoiding any
      -- slice of a function result
      declare_free := hex2slv(crchex(1)) & hex2slv(crchex(2))
                    & hex2slv(crchex(3)) & hex2slv(crchex(4));
      expected := declare_free(14 downto 0);

      -- ---- clear the register ----
      wait until falling_edge(clk);
      crc_clr <= '1';
      wait until falling_edge(clk);
      crc_clr <= '0';

      -- ---- feed the bits ----
      for i in 1 to nbits loop
        wait until falling_edge(clk);
        if bitstr(i) = '1' then
          crc_in <= '1';
        else
          crc_in <= '0';
        end if;
        crc_en <= '1';
        wait until falling_edge(clk);
        crc_en <= '0';
      end loop;

      -- crc_out is valid now (registered value, one clock settled)
      wait until falling_edge(clk);
      got := crc_out;

      nvec := nvec + 1;
      if got /= expected then
        nfail := nfail + 1;
        if not first_fail_shown then
          report "FIRST MISMATCH at vector " & integer'image(nvec)
               & ": nbits=" & integer'image(nbits)
               & " expected=" & slv2hex(expected)
               & " got=" & slv2hex(got)
            severity error;
          first_fail_shown := true;
        end if;
      end if;
    end loop;

    file_close(vfile);

    report "=========================================" severity note;
    report "CRC-15 vectors checked : " & integer'image(nvec)
      severity note;
    report "CRC-15 mismatches      : " & integer'image(nfail)
      severity note;
    report "=========================================" severity note;

    assert nfail = 0
      report "FAIL: " & integer'image(nfail) & " of "
             & integer'image(nvec) & " CRC vectors mismatched"
      severity error;

    if nfail = 0 then
      report "==== ALL " & integer'image(nvec)
           & " CRC-15 VECTORS MATCH THE REFERENCE ====" severity note;
    end if;

    done <= true;
    wait;
  end process;

  -- ---- timeout guard ----
  -- A run truncated by --stop-time prints no summary and asserts
  -- nothing, so run.sh reports PASS on a testbench that never
  -- finished. Day 25: a 3 ms limit silently cut this off at about
  -- vector 290 and still showed PASS. This process fires if the
  -- stimulus has not set done by the deadline.
  guard : process
  begin
    wait for 14 ms;
    assert done
      report "FAIL: testbench did not complete before the timeout "
             & "- increase --stop-time"
      severity error;
    wait;
  end process;

end sim;
