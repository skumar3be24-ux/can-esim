-- ============================================================
-- Self-checking testbench for shift11.
--
-- Loads Node A's real CAN identifier (0x0A5) and verifies that
-- all 11 bits come out MSB first in the correct order.
--
--   0x0A5 = 0000 1010 0101
--   low 11 bits            = 000 1010 0101
--   MSB-first serial order = 0 0 0 1 0 1 0 0 1 0 1
--
-- This is the same bit sequence Node A will drive onto CANH/CANL
-- during arbitration on Day 66.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_shift11 is
end entity;

architecture sim of tb_shift11 is

    signal clk       : std_logic := '0';
    signal rst       : std_logic := '1';
    signal load      : std_logic := '0';
    signal shift     : std_logic := '0';
    signal din       : std_logic_vector(10 downto 0) := (others => '0');
    signal sout      : std_logic;
    signal bits_left : std_logic_vector(3 downto 0);
    signal empty     : std_logic;

    constant HALF_PERIOD : time := 250 ns;   -- 2 MHz project clock

    -- Node A identifier, 11 bits
    constant NODE_A_ID : std_logic_vector(10 downto 0) := "00010100101";

    -- Same bits, ascending index, so EXPECTED(0) is the first on the wire
    constant EXPECTED : std_logic_vector(0 to 10) := "00010100101";

begin

    uut : entity work.shift11
        port map (
            clk       => clk,
            rst       => rst,
            load      => load,
            shift     => shift,
            din       => din,
            sout      => sout,
            bits_left => bits_left,
            empty     => empty
        );

    clk <= not clk after HALF_PERIOD;

    stim : process
    begin
        --------------------------------------------------------
        -- 1. After reset the line is recessive and register empty
        --------------------------------------------------------
        rst <= '1';
        wait for 1 us;

        assert sout = '1'
            report "FAIL 1: sout not recessive after reset"
            severity error;
        assert empty = '1'
            report "FAIL 1: empty not asserted after reset"
            severity error;

        rst <= '0';
        wait until rising_edge(clk);

        --------------------------------------------------------
        -- 2. Parallel load
        --------------------------------------------------------
        din  <= NODE_A_ID;
        load <= '1';
        wait until rising_edge(clk);
        load <= '0';
        wait for 1 ns;

        assert bits_left = "1011"        -- 11
            report "FAIL 2: bits_left not 11 after load"
            severity error;
        assert empty = '0'
            report "FAIL 2: empty asserted immediately after load"
            severity error;

        --------------------------------------------------------
        -- 3. Shift all 11 bits out, MSB first
        --------------------------------------------------------
        for i in 0 to 10 loop
            assert sout = EXPECTED(i)
                report "FAIL 3: ID bit " & integer'image(10 - i) &
                       " wrong (serial position " & integer'image(i) & ")"
                severity error;

            shift <= '1';
            wait until rising_edge(clk);
            wait for 1 ns;
        end loop;

        shift <= '0';

        --------------------------------------------------------
        -- 4. Register drained, line returns recessive
        --------------------------------------------------------
        assert empty = '1'
            report "FAIL 4: empty not asserted after 11 shifts"
            severity error;
        assert sout = '1'
            report "FAIL 4: line not recessive after drain"
            severity error;

        --------------------------------------------------------
        report "===== ALL SHIFT11 CHECKS PASSED =====" severity note;
        wait;
    end process;

end architecture;
