-- ============================================================
-- Self-checking testbench for counter.
--
-- Rule 3 of the project: a test must TELL you it passed, not
-- require you to squint at a waveform. Every check is an assert.
--
-- Run with --assert-level=error so a failure returns a non-zero
-- exit code; that is what makes regress.sh work later.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- A testbench has NO ports. It is the outermost level.
entity tb_counter is
end entity;

architecture sim of tb_counter is

    signal clk   : std_logic := '0';
    signal rst   : std_logic := '1';
    signal en    : std_logic := '0';
    signal count : std_logic_vector(7 downto 0);

    -- Project clock: 2 MHz -> 500 ns period -> 250 ns half period
    constant HALF_PERIOD : time := 250 ns;

begin

    -- Device Under Test
    uut : entity work.counter
        port map (
            clk   => clk,
            rst   => rst,
            en    => en,
            count => count
        );

    -- Free-running clock. This concurrent statement runs forever,
    -- which is why --stop-time is mandatory.
    clk <= not clk after HALF_PERIOD;

    stim : process
    begin
        --------------------------------------------------------
        -- 1. Reset behaviour
        --------------------------------------------------------
        rst <= '1';
        en  <= '0';
        wait for 1 us;

        assert count = x"00"
            report "FAIL 1: counter not zero during reset"
            severity error;

        rst <= '0';
        wait until rising_edge(clk);

        --------------------------------------------------------
        -- 2. Counting with enable
        --------------------------------------------------------
        en <= '1';

        for i in 1 to 10 loop
            wait until rising_edge(clk);
        end loop;

        wait for 1 ns;   -- let the signal settle after the edge

        assert count = x"0A"
            report "FAIL 2: expected count = 10 after 10 enabled clocks"
            severity error;

        --------------------------------------------------------
        -- 3. Hold when disabled
        --------------------------------------------------------
        en <= '0';

        for i in 1 to 10 loop
            wait until rising_edge(clk);
        end loop;

        wait for 1 ns;

        assert count = x"0A"
            report "FAIL 3: counter moved while enable was low"
            severity error;

        --------------------------------------------------------
        -- 4. Asynchronous reset takes effect immediately
        --------------------------------------------------------
        rst <= '1';
        wait for 10 ns;          -- deliberately NOT a clock edge

        assert count = x"00"
            report "FAIL 4: async reset did not clear the counter"
            severity error;

        --------------------------------------------------------
        report "===== ALL COUNTER CHECKS PASSED =====" severity note;
        wait;   -- stop this process forever
    end process;

end architecture;
