-- ============================================================
-- 8-bit up counter with enable and asynchronous reset.
--
-- Also demonstrates the signal-assignment delay rule:
-- 'a' and 'b' form a two-stage delay chain even though they are
-- assigned on adjacent lines. See the process below.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;   -- std_logic, std_logic_vector
use ieee.numeric_std.all;      -- unsigned, arithmetic, conversions

entity counter is
    port (
        clk   : in  std_logic;                     -- 2 MHz project clock
        rst   : in  std_logic;                     -- active high, async
        en    : in  std_logic;                     -- count enable
        count : out std_logic_vector(7 downto 0)
    );
end entity;

architecture rtl of counter is

    -- Internal state is 'unsigned' so we can do arithmetic on it.
    -- std_logic_vector has no '+' operator - it is just a bag of bits.
    signal cnt : unsigned(7 downto 0) := (others => '0');

    -- Demonstration signals for the signal-delay rule.
    signal a : unsigned(7 downto 0) := (others => '0');
    signal b : unsigned(7 downto 0) := (others => '0');

begin

    process (clk, rst)
    begin
        if rst = '1' then
            -- ASYNCHRONOUS reset: immediate, not on a clock edge.
            cnt <= (others => '0');
            a   <= (others => '0');
            b   <= (others => '0');

        elsif rising_edge(clk) then
            -- SYNCHRONOUS logic: only on the 0 -> 1 transition of clk.
            if en = '1' then
                cnt <= cnt + 1;
            end if;

            -- These two lines LOOK sequential but are not.
            -- Signal assignments do not take effect until the process
            -- suspends, so 'b' receives the value 'a' held when this
            -- process started - NOT the value being assigned one line up.
            -- Result: a lags cnt by one clock, b lags a by one clock.
            a <= cnt;
            b <= a;
        end if;
    end process;

    -- Concurrent assignment: continuous, outside any process.
    count <= std_logic_vector(cnt);

end architecture;
