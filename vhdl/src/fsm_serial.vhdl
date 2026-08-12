-- ============================================================
-- fsm_serial : miniature frame transmitter
--
-- This is a deliberately small version of can_tx_fsm. It sends:
--
--     IDLE  : line held recessive ('1')
--     SOF   : one dominant bit ('0')       <- start of frame
--     DATA  : 8 bits of PATTERN, MSB first
--     EOF   : 3 recessive bits ('1')       <- end of frame
--     back to IDLE
--
-- Output sequence for PATTERN = 0xA5 (10100101):
--
--     0 1 0 1 0 0 1 0 1 1 1 1
--     ^ \_____________/ \___/
--    SOF      DATA        EOF
--
-- The real can_tx_fsm adds ID, RTR, IDE, r0, DLC, CRC, ACK and
-- interframe space - but the skeleton is exactly this.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fsm_serial is
    port (
        clk   : in  std_logic;
        rst   : in  std_logic;
        start : in  std_logic;   -- pulse to begin a frame
        dout  : out std_logic;   -- serial output
        busy  : out std_logic    -- high while a frame is in progress
    );
end entity;

architecture rtl of fsm_serial is

    -- An enumerated type. The synthesiser picks the encoding; you
    -- just name the states. Far safer than integer state numbers.
    type state_t is (IDLE, SOF, DATA, EOF_FIELD);

    signal state : state_t := IDLE;

    -- Payload. A constant, not a generic - NGHDL does not pass
    -- generics through, so the whole project uses constants.
    constant PATTERN : std_logic_vector(7 downto 0) := x"A5";

    -- Which data bit we are sending. Counts DOWN because CAN is
    -- MSB first: bit 7 goes out before bit 0.
    signal bit_index : integer range 0 to 7 := 7;

    -- How many EOF bits sent so far.
    signal eof_count : integer range 0 to 3 := 0;

begin

    ---------------------------------------------------------------
    -- State register + next-state logic, in one clocked process.
    ---------------------------------------------------------------
    process (clk, rst)
    begin
        if rst = '1' then
            state     <= IDLE;
            bit_index <= 7;
            eof_count <= 0;

        elsif rising_edge(clk) then
            case state is

                when IDLE =>
                    bit_index <= 7;
                    eof_count <= 0;
                    if start = '1' then
                        state <= SOF;
                    end if;

                when SOF =>
                    -- SOF is exactly one bit long, so we always leave.
                    state <= DATA;

                when DATA =>
                    if bit_index = 0 then
                        state <= EOF_FIELD;
                    else
                        bit_index <= bit_index - 1;
                    end if;

                when EOF_FIELD =>
                    if eof_count = 2 then
                        state <= IDLE;
                    else
                        eof_count <= eof_count + 1;
                    end if;

                -- Always include 'when others'. It prevents inferred
                -- latches and stops an illegal state locking the design.
                when others =>
                    state <= IDLE;

            end case;
        end if;
    end process;

    ---------------------------------------------------------------
    -- Output logic: concurrent, a pure function of the state.
    -- This is a Moore machine - outputs depend only on state.
    ---------------------------------------------------------------
    dout <= '0'                  when state = SOF  else
            PATTERN(bit_index)   when state = DATA else
            '1';                 -- IDLE and EOF are recessive

    busy <= '0' when state = IDLE else '1';

end architecture;
