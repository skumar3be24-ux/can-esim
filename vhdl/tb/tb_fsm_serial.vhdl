-- ============================================================
-- Self-checking testbench for fsm_serial.
--
-- Checks the complete 12-bit output sequence bit by bit against
-- an expected constant. This is exactly how you will verify
-- can_tx_fsm on Day 34 - just with a longer expected vector.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_fsm_serial is
end entity;

architecture sim of tb_fsm_serial is

    signal clk   : std_logic := '0';
    signal rst   : std_logic := '1';
    signal start : std_logic := '0';
    signal dout  : std_logic;
    signal busy  : std_logic;

    constant HALF_PERIOD : time := 250 ns;   -- 2 MHz project clock

    -- Expected serial stream, ascending index so EXPECTED(0) is the
    -- first bit on the wire:
    --      SOF  DATA(0xA5 MSB first)  EOF
    --       0   1 0 1 0 0 1 0 1       1 1 1
    constant EXPECTED : std_logic_vector(0 to 11) := "010100101111";

    -- Names for the report messages, so a failure tells you which
    -- field went wrong rather than just a bit number.
    type name_array is array (0 to 11) of string(1 to 4);
    constant FIELD : name_array :=
        ("SOF ",
         "D7  ", "D6  ", "D5  ", "D4  ", "D3  ", "D2  ", "D1  ", "D0  ",
         "EOF1", "EOF2", "EOF3");

begin

    uut : entity work.fsm_serial
        port map (
            clk   => clk,
            rst   => rst,
            start => start,
            dout  => dout,
            busy  => busy
        );

    clk <= not clk after HALF_PERIOD;

    stim : process
    begin
        --------------------------------------------------------
        -- 1. Idle line must be recessive
        --------------------------------------------------------
        rst <= '1';
        wait for 1 us;

        assert dout = '1'
            report "FAIL: line not recessive during reset"
            severity error;
        assert busy = '0'
            report "FAIL: busy asserted during reset"
            severity error;

        rst <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;

        assert dout = '1'
            report "FAIL: line not recessive when idle"
            severity error;

        --------------------------------------------------------
        -- 2. Send a frame and check every bit
        --------------------------------------------------------
        start <= '1';
        wait until rising_edge(clk);   -- this edge moves IDLE -> SOF
        start <= '0';

        for i in 0 to 11 loop
            wait for 1 ns;             -- let the output settle
            assert dout = EXPECTED(i)
                report "FAIL at bit " & integer'image(i) &
                       " (" & FIELD(i) & ")"
                severity error;
            wait until rising_edge(clk);
        end loop;

        --------------------------------------------------------
        -- 3. Must return to idle and release busy
        --------------------------------------------------------
        wait for 1 ns;

        assert busy = '0'
            report "FAIL: busy still asserted after frame"
            severity error;
        assert dout = '1'
            report "FAIL: line not recessive after frame"
            severity error;

        --------------------------------------------------------
        report "===== ALL FSM_SERIAL CHECKS PASSED =====" severity note;
        wait;
    end process;

end architecture;
