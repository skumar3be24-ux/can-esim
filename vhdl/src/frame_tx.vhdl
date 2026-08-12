-- ============================================================
-- frame_tx : hierarchical frame transmitter
--
-- Instantiates shift11 inside an FSM to transmit:
--
--     IDLE      : recessive
--     SOF       : one dominant bit
--     ID_FIELD  : 11 identifier bits, MSB first (from shift11)
--     EOF_FIELD : 3 recessive bits
--
-- This is the first genuinely hierarchical design in the project
-- and is a direct cut-down of can_tx_fsm. The full version adds
-- RTR, IDE, r0, DLC, data, CRC, ACK and interframe space, plus a
-- bit stuffer between the FSM and the output.
--
-- Demonstrates: component instantiation with named port map,
-- and driving a submodule's control inputs from FSM state.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity frame_tx is
    port (
        clk   : in  std_logic;
        rst   : in  std_logic;
        start : in  std_logic;
        id    : in  std_logic_vector(10 downto 0);
        tx    : out std_logic;
        busy  : out std_logic
    );
end entity;

architecture rtl of frame_tx is

    type state_t is (IDLE, SOF, ID_FIELD, EOF_FIELD);
    signal state : state_t := IDLE;

    signal eof_count : integer range 0 to 3 := 0;

    -- Wires between this level and the shift11 instance
    signal sr_load      : std_logic := '0';
    signal sr_shift     : std_logic := '0';
    signal sr_sout      : std_logic;
    signal sr_bits_left : std_logic_vector(3 downto 0);
    signal sr_empty     : std_logic;

begin

    ---------------------------------------------------------------
    -- Submodule instantiation.
    --
    -- Direct entity instantiation with NAMED association
    -- (formal => actual). Always use named association: positional
    -- association silently breaks the moment a port list changes.
    ---------------------------------------------------------------
    u_shift : entity work.shift11
        port map (
            clk       => clk,
            rst       => rst,
            load      => sr_load,
            shift     => sr_shift,
            din       => id,
            sout      => sr_sout,
            bits_left => sr_bits_left,
            empty     => sr_empty
        );

    ---------------------------------------------------------------
    -- Control FSM
    ---------------------------------------------------------------
    process (clk, rst)
    begin
        if rst = '1' then
            state     <= IDLE;
            eof_count <= 0;

        elsif rising_edge(clk) then
            case state is

                when IDLE =>
                    eof_count <= 0;
                    if start = '1' then
                        state <= SOF;   -- sr_load is asserted this cycle
                    end if;

                when SOF =>
                    -- One dominant bit. The shift register now holds
                    -- the ID with sout already presenting bit 10.
                    state <= ID_FIELD;

                when ID_FIELD =>
                    -- bits_left counts down as bits are consumed.
                    -- When it reaches 1 the LAST bit is on the wire
                    -- this cycle, so the next cycle belongs to EOF.
                    if sr_bits_left = "0001" then
                        state <= EOF_FIELD;
                    end if;

                when EOF_FIELD =>
                    if eof_count = 2 then
                        state <= IDLE;
                    else
                        eof_count <= eof_count + 1;
                    end if;

                when others =>
                    state <= IDLE;

            end case;
        end if;
    end process;

    ---------------------------------------------------------------
    -- Submodule control, derived from state
    ---------------------------------------------------------------

    -- Load the identifier on the cycle we leave IDLE.
    sr_load  <= '1' when (state = IDLE and start = '1') else '0';

    -- Advance one bit per clock while sending the identifier.
    sr_shift <= '1' when state = ID_FIELD else '0';

    ---------------------------------------------------------------
    -- Output multiplexer
    ---------------------------------------------------------------
    tx <= '0'      when state = SOF      else
          sr_sout  when state = ID_FIELD else
          '1';     -- IDLE and EOF are recessive

    busy <= '0' when state = IDLE else '1';

end architecture;
