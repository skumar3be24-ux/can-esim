-- ============================================================
-- Self-checking testbench for frame_tx.
--
-- Verifies the complete 15-bit output stream for Node A:
--
--   SOF  identifier 0x0A5 (MSB first)  EOF
--    0   0 0 0 1 0 1 0 0 1 0 1         1 1 1
--
-- Then repeats with Node B (0x123) to prove the design is not
-- accidentally hard-wired to one identifier.
--
-- NOTE: 'label' is a VHDL reserved word and cannot be used as an
-- identifier. The procedure parameter is named frame_name.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_frame_tx is
end entity;

architecture sim of tb_frame_tx is

    signal clk   : std_logic := '0';
    signal rst   : std_logic := '1';
    signal start : std_logic := '0';
    signal id    : std_logic_vector(10 downto 0) := (others => '0');
    signal tx    : std_logic;
    signal busy  : std_logic;

    constant HALF_PERIOD : time := 250 ns;   -- 2 MHz project clock

    constant ID_A : std_logic_vector(10 downto 0) := "00010100101";  -- 0x0A5
    constant ID_B : std_logic_vector(10 downto 0) := "00100100011";  -- 0x123

    -- SOF + 11 ID bits + 3 EOF bits
    constant EXP_A : std_logic_vector(0 to 14) := "0" & "00010100101" & "111";
    constant EXP_B : std_logic_vector(0 to 14) := "0" & "00100100011" & "111";

    -- Field names so a failure says WHERE, not just which index
    type name_array is array (0 to 14) of string(1 to 5);
    constant FIELD : name_array :=
        ("SOF  ",
         "ID10 ", "ID9  ", "ID8  ", "ID7  ", "ID6  ", "ID5  ",
         "ID4  ", "ID3  ", "ID2  ", "ID1  ", "ID0  ",
         "EOF1 ", "EOF2 ", "EOF3 ");

    -- Shared checking routine so both frames are tested identically
    procedure check_frame (
        signal   clk_s      : in std_logic;
        signal   tx_s       : in std_logic;
        constant expect     : in std_logic_vector(0 to 14);
        constant frame_name : in string
    ) is
    begin
        for i in 0 to 14 loop
            wait for 1 ns;
            assert tx_s = expect(i)
                report "FAIL [" & frame_name & "] bit " &
                       integer'image(i) & " (" & FIELD(i) & ")"
                severity error;
            wait until rising_edge(clk_s);
        end loop;
    end procedure;

begin

    uut : entity work.frame_tx
        port map (
            clk   => clk,
            rst   => rst,
            start => start,
            id    => id,
            tx    => tx,
            busy  => busy
        );

    clk <= not clk after HALF_PERIOD;

    stim : process
    begin
        --------------------------------------------------------
        -- 1. Idle state
        --------------------------------------------------------
        rst <= '1';
        wait for 1 us;

        assert tx = '1'
            report "FAIL: line not recessive during reset"
            severity error;
        assert busy = '0'
            report "FAIL: busy asserted during reset"
            severity error;

        rst <= '0';
        wait until rising_edge(clk);

        --------------------------------------------------------
        -- 2. Transmit Node A's identifier
        --------------------------------------------------------
        id    <= ID_A;
        start <= '1';
        wait until rising_edge(clk);     -- IDLE -> SOF, shift11 loads
        start <= '0';

        check_frame(clk, tx, EXP_A, "Node A");

        wait for 1 ns;
        assert busy = '0'
            report "FAIL: busy still high after Node A frame"
            severity error;

        --------------------------------------------------------
        -- 3. Transmit Node B's identifier - proves it is not
        --    hard-wired to one value
        --------------------------------------------------------
        wait until rising_edge(clk);
        id    <= ID_B;
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        check_frame(clk, tx, EXP_B, "Node B");

        wait for 1 ns;
        assert busy = '0'
            report "FAIL: busy still high after Node B frame"
            severity error;

        --------------------------------------------------------
        report "===== ALL FRAME_TX CHECKS PASSED =====" severity note;
        wait;
    end process;

end architecture;
