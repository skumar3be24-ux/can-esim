-- ============================================================
-- shift11 : 11-bit parallel-load, MSB-first serial shift register
--
-- This is the exact mechanism can_tx_fsm uses to put the CAN
-- identifier on the bus: load the 11-bit ID, then shift it out
-- one bit per bit-time, most significant bit first.
--
-- Demonstrates:
--   * std_logic_vector slicing and concatenation
--   * MSB-first shifting
--   * unsigned <-> std_logic_vector <-> integer conversion
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity shift11 is
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        load      : in  std_logic;                      -- capture din
        shift     : in  std_logic;                      -- advance one bit
        din       : in  std_logic_vector(10 downto 0);  -- e.g. CAN ID
        sout      : out std_logic;                      -- serial out, MSB first
        bits_left : out std_logic_vector(3 downto 0);   -- 0..11 remaining
        empty     : out std_logic
    );
end entity;

architecture rtl of shift11 is

    -- The shift register itself.
    signal sr : std_logic_vector(10 downto 0) := (others => '1');

    -- How many bits remain to be shifted out.
    -- Kept as an integer internally because arithmetic on integers
    -- is simple and readable; converted at the port boundary.
    signal count : integer range 0 to 11 := 0;

begin

    process (clk, rst)
    begin
        if rst = '1' then
            sr    <= (others => '1');   -- recessive idle line
            count <= 0;

        elsif rising_edge(clk) then

            if load = '1' then
                -- Parallel load. All 11 bits captured in one clock.
                sr    <= din;
                count <= 11;

            elsif shift = '1' and count > 0 then
                -- MSB-first shift.
                --
                --   sr(9 downto 0)  = the lower 10 bits
                --   & '1'           = concatenate a recessive bit in
                --
                -- The right-hand side uses the OLD value of sr, which
                -- is exactly why this works (see Day 6).
                sr    <= sr(9 downto 0) & '1';
                count <= count - 1;
            end if;

        end if;
    end process;

    -- Serial output is always the top bit of the register.
    sout <= sr(10);

    -- Conversion at the port boundary:
    --   integer -> unsigned -> std_logic_vector
    bits_left <= std_logic_vector(to_unsigned(count, 4));

    empty <= '1' when count = 0 else '0';

end architecture;
