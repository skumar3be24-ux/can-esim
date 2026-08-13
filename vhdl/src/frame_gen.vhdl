-- ============================================================
-- CAN standard frame generator (transmit path)
-- Day 26, Phase 3
--
-- Assembles a complete standard (11-bit identifier) CAN data
-- frame and emits it one bit per bit_en pulse.
--
-- FRAME FORMAT - field, width, stuffing
--
--   SOF             1    dominant                  stuffed
--   Identifier     11    ID(10..0), MSB first      stuffed
--   RTR             1    0 = data frame            stuffed
--   IDE             1    0 = standard format       stuffed
--   r0              1    reserved, dominant        stuffed
--   DLC             4    data length 0..8          stuffed
--   Data        0..64    payload, MSB first        stuffed
--   CRC sequence   15    over all of the above     stuffed
--   CRC delimiter   1    recessive                 NOT stuffed
--   ACK slot        1    transmitter sends rec.    NOT stuffed
--   ACK delimiter   1    recessive                 NOT stuffed
--   EOF             7    recessive                 NOT stuffed
--   IFS             3    recessive                 NOT stuffed
--
--   DLC=0 -> 44 bits before stuffing
--   DLC=8 -> 108 bits before stuffing
--
-- THE STUFF BOUNDARY IS THE POINT OF THIS MODULE
--   stuff_en must be high from SOF through the LAST CRC bit and
--   low from the CRC delimiter onward. One bit either way
--   corrupts every frame. This FSM drives it as a real signal
--   rather than leaving it as a comment, and the testbench
--   checks the transition bit-exactly.
--
-- CRC COVERAGE
--   The CRC is fed from SOF through the end of the data field -
--   NOT over the CRC sequence itself, and NOT over any field
--   after it. crc_en is asserted only during those fields.
--   The CRC is also computed on the DESTUFFED bits, which is
--   automatic here because this module emits payload bits and
--   the stuffer sits downstream.
--
-- ACK SLOT
--   The TRANSMITTER sends recessive in the ACK slot. A receiver
--   that accepted the frame overwrites it with dominant. This
--   module always sends recessive; ACK checking is the receiver
--   FSM's job (Phase 4).
--
-- INTERFACE
--   Pulse frame_start with id/rtr/dlc/data valid. The module
--   then emits one bit per bit_en pulse on tx_bit, with
--   stuff_en indicating whether the downstream stuffer should be
--   active. frame_active is high for the whole frame and drops
--   after the last IFS bit.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity frame_gen is
  port (
    clk         : in  std_logic;
    reset_n     : in  std_logic;

    -- ---- frame request ----
    frame_start : in  std_logic;                      -- one-cycle pulse
    id_in       : in  std_logic_vector(10 downto 0);
    rtr_in      : in  std_logic;
    dlc_in      : in  std_logic_vector(3 downto 0);
    data_in     : in  std_logic_vector(63 downto 0);  -- MSB = first byte

    -- ---- bit-rate interface ----
    bit_en      : in  std_logic;   -- one pulse per bit slot
    tx_bit      : out std_logic;   -- the bit to transmit
    stuff_en    : out std_logic;   -- downstream stuffing active
    frame_active: out std_logic;   -- high for the whole frame

    -- ---- CRC interface ----
    crc_clr     : out std_logic;
    crc_en      : out std_logic;
    crc_bit     : out std_logic;
    crc_val     : in  std_logic_vector(14 downto 0);

    -- ---- status ----
    field_id    : out std_logic_vector(3 downto 0)    -- current field
  );
end frame_gen;

architecture rtl of frame_gen is

  type state_t is (
    ST_IDLE, ST_SOF, ST_ID, ST_RTR, ST_IDE, ST_R0, ST_DLC,
    ST_DATA, ST_CRC, ST_CRCDEL, ST_ACK, ST_ACKDEL, ST_EOF, ST_IFS
  );
  signal state : state_t := ST_IDLE;

  -- field encodings for the status output
  constant F_IDLE   : std_logic_vector(3 downto 0) := x"0";
  constant F_SOF    : std_logic_vector(3 downto 0) := x"1";
  constant F_ID     : std_logic_vector(3 downto 0) := x"2";
  constant F_RTR    : std_logic_vector(3 downto 0) := x"3";
  constant F_IDE    : std_logic_vector(3 downto 0) := x"4";
  constant F_R0     : std_logic_vector(3 downto 0) := x"5";
  constant F_DLC    : std_logic_vector(3 downto 0) := x"6";
  constant F_DATA   : std_logic_vector(3 downto 0) := x"7";
  constant F_CRC    : std_logic_vector(3 downto 0) := x"8";
  constant F_CRCDEL : std_logic_vector(3 downto 0) := x"9";
  constant F_ACK    : std_logic_vector(3 downto 0) := x"A";
  constant F_ACKDEL : std_logic_vector(3 downto 0) := x"B";
  constant F_EOF    : std_logic_vector(3 downto 0) := x"C";
  constant F_IFS    : std_logic_vector(3 downto 0) := x"D";

  -- latched frame contents
  signal id_r   : std_logic_vector(10 downto 0) := (others => '0');
  signal rtr_r  : std_logic := '0';
  signal dlc_r  : std_logic_vector(3 downto 0) := (others => '0');
  signal data_r : std_logic_vector(63 downto 0) := (others => '0');
  signal nbytes : integer range 0 to 8 := 0;

  signal bitcnt : integer range 0 to 63 := 0;

  signal tx_r    : std_logic := '1';
  signal stuff_r : std_logic := '0';
  signal act_r   : std_logic := '0';
  signal cclr_r  : std_logic := '0';
  signal cen_r   : std_logic := '0';
  signal cbit_r  : std_logic := '0';
  signal field_r : std_logic_vector(3 downto 0) := F_IDLE;

  -- CRC value latched when the data field ends, so it stays
  -- stable while it is being shifted out
  signal crc_lat : std_logic_vector(14 downto 0) := (others => '0');

begin

  process(clk, reset_n)
    variable dlc_int : integer range 0 to 15;
  begin
    if reset_n = '0' then
      state   <= ST_IDLE;
      bitcnt  <= 0;
      tx_r    <= '1';
      stuff_r <= '0';
      act_r   <= '0';
      cclr_r  <= '0';
      cen_r   <= '0';
      cbit_r  <= '0';
      field_r <= F_IDLE;
      nbytes  <= 0;

    elsif rising_edge(clk) then
      cclr_r <= '0';
      cen_r  <= '0';

      if state = ST_IDLE then
        tx_r    <= '1';           -- bus idle is recessive
        stuff_r <= '0';
        act_r   <= '0';
        field_r <= F_IDLE;

        if frame_start = '1' then
          -- latch the frame contents
          id_r   <= id_in;
          rtr_r  <= rtr_in;
          dlc_r  <= dlc_in;
          data_r <= data_in;

          dlc_int := to_integer(unsigned(dlc_in));
          if dlc_int > 8 then
            nbytes <= 8;          -- DLC > 8 is treated as 8
          else
            nbytes <= dlc_int;
          end if;

          cclr_r <= '1';          -- reset the CRC register
          state  <= ST_SOF;
          bitcnt <= 0;
          act_r  <= '1';
        end if;

      elsif bit_en = '1' then
        -- ============ one bit slot ============
        case state is

          when ST_SOF =>
            tx_r    <= '0';       -- SOF is dominant
            stuff_r <= '1';
            field_r <= F_SOF;
            cen_r   <= '1';
            cbit_r  <= '0';
            state   <= ST_ID;
            bitcnt  <= 0;

          when ST_ID =>
            tx_r    <= id_r(10 - bitcnt);
            stuff_r <= '1';
            field_r <= F_ID;
            cen_r   <= '1';
            cbit_r  <= id_r(10 - bitcnt);
            if bitcnt = 10 then
              state  <= ST_RTR;
              bitcnt <= 0;
            else
              bitcnt <= bitcnt + 1;
            end if;

          when ST_RTR =>
            tx_r    <= rtr_r;
            stuff_r <= '1';
            field_r <= F_RTR;
            cen_r   <= '1';
            cbit_r  <= rtr_r;
            state   <= ST_IDE;

          when ST_IDE =>
            tx_r    <= '0';       -- standard format
            stuff_r <= '1';
            field_r <= F_IDE;
            cen_r   <= '1';
            cbit_r  <= '0';
            state   <= ST_R0;

          when ST_R0 =>
            tx_r    <= '0';       -- reserved, dominant
            stuff_r <= '1';
            field_r <= F_R0;
            cen_r   <= '1';
            cbit_r  <= '0';
            state   <= ST_DLC;
            bitcnt  <= 0;

          when ST_DLC =>
            tx_r    <= dlc_r(3 - bitcnt);
            stuff_r <= '1';
            field_r <= F_DLC;
            cen_r   <= '1';
            cbit_r  <= dlc_r(3 - bitcnt);
            if bitcnt = 3 then
              bitcnt <= 0;
              if nbytes = 0 then
                -- no data field: latch the CRC and go straight to it
                state <= ST_CRC;
              else
                state <= ST_DATA;
              end if;
            else
              bitcnt <= bitcnt + 1;
            end if;

          when ST_DATA =>
            tx_r    <= data_r(63 - bitcnt);
            stuff_r <= '1';
            field_r <= F_DATA;
            cen_r   <= '1';
            cbit_r  <= data_r(63 - bitcnt);
            if bitcnt = (nbytes * 8) - 1 then
              state  <= ST_CRC;
              bitcnt <= 0;
            else
              bitcnt <= bitcnt + 1;
            end if;

          when ST_CRC =>
            -- crc_val is stable now: the last cen_r pulse was the
            -- previous slot, so the register has settled.
            if bitcnt = 0 then
              crc_lat <= crc_val;
              tx_r    <= crc_val(14);
            else
              tx_r    <= crc_lat(14 - bitcnt);
            end if;
            stuff_r <= '1';       -- CRC sequence IS stuffed
            field_r <= F_CRC;
            -- crc_en NOT asserted: the CRC does not cover itself
            if bitcnt = 14 then
              state  <= ST_CRCDEL;
              bitcnt <= 0;
            else
              bitcnt <= bitcnt + 1;
            end if;

          when ST_CRCDEL =>
            tx_r    <= '1';       -- recessive
            stuff_r <= '0';       -- <<< STUFFING STOPS HERE
            field_r <= F_CRCDEL;
            state   <= ST_ACK;

          when ST_ACK =>
            tx_r    <= '1';       -- transmitter sends recessive
            stuff_r <= '0';
            field_r <= F_ACK;
            state   <= ST_ACKDEL;

          when ST_ACKDEL =>
            tx_r    <= '1';
            stuff_r <= '0';
            field_r <= F_ACKDEL;
            state   <= ST_EOF;
            bitcnt  <= 0;

          when ST_EOF =>
            tx_r    <= '1';
            stuff_r <= '0';
            field_r <= F_EOF;
            if bitcnt = 6 then    -- 7 bits
              state  <= ST_IFS;
              bitcnt <= 0;
              -- THE FRAME ENDS HERE. Interframe space is NOT part
              -- of the frame; it is the gap before the next one,
              -- during which the bus is idle and any node may
              -- start transmitting. Holding frame_active through
              -- IFS would block arbitration for 3 bit times.
              act_r  <= '0';
            else
              bitcnt <= bitcnt + 1;
            end if;

          when ST_IFS =>
            -- still emitting recessive bits, but frame_active is
            -- already low - the bus is available.
            tx_r    <= '1';
            stuff_r <= '0';
            field_r <= F_IFS;
            if bitcnt = 2 then    -- 3 bits
              state  <= ST_IDLE;
              bitcnt <= 0;
            else
              bitcnt <= bitcnt + 1;
            end if;

          when others =>
            state <= ST_IDLE;

        end case;
      end if;
    end if;
  end process;

  tx_bit       <= tx_r;
  stuff_en     <= stuff_r;
  frame_active <= act_r;
  crc_clr      <= cclr_r;
  crc_en       <= cen_r;
  crc_bit      <= cbit_r;
  field_id     <= field_r;

end rtl;
