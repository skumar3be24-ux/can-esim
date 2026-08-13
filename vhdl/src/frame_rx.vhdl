-- ============================================================
-- CAN standard frame decoder (receive path)
-- Day 28, Phase 4
--
-- Consumes destuffed payload bits, walks the frame fields, feeds
-- the CRC over the covered portion, compares the received CRC
-- against the computed one, and extracts ID / RTR / DLC / data.
--
-- FIELD SEQUENCE (mirror of frame_gen)
--   SOF            1   must be dominant
--   Identifier    11   MSB first
--   RTR            1
--   IDE            1   0 = standard (1 = extended, not handled yet)
--   r0             1   reserved
--   DLC            4
--   Data       0..64
--   CRC sequence  15   compared against the computed CRC
--   CRC delimiter  1   must be recessive  -> form error if not
--   ACK slot       1   receiver may drive dominant here
--   ACK delimiter  1   must be recessive  -> form error if not
--   EOF            7   must be recessive  -> form error if not
--
-- STUFFING SCOPE
--   rx_stuff_en is high from SOF through the last CRC bit and low
--   from the CRC delimiter onward. It is driven COMBINATIONALLY
--   from the state, because the destuffer needs it DURING the bit
--   slot. A registered version arrives a slot late and the
--   destuffer would try to destuff the fixed-form fields.
--   (Day 27 lesson: back-pressure and enables across a module
--   boundary must be valid in the slot they describe.)
--
-- CRC COVERAGE
--   crc_en is asserted from SOF through the end of the data field
--   only. The CRC does not cover itself or anything after it.
--   Because this module consumes DESTUFFED bits, the CRC is
--   automatically computed on the payload, never on stuff bits.
--
-- ERROR OUTPUTS (one-cycle pulses, raised at the end of a frame)
--   crc_err   received CRC sequence does not match the computed one
--   form_err  a fixed-form bit was dominant where the standard
--             requires recessive
--   Stuff errors come from the destuffer and are passed through.
--
-- WHAT IS NOT HERE YET
--   No ACK generation (the receiver should drive dominant in the
--   ACK slot - Day 29), no error frames (Phase 5), no extended
--   identifiers, no overload frames.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity frame_rx is
  port (
    clk       : in  std_logic;
    reset_n   : in  std_logic;

    -- ---- destuffed bit input ----
    bit_valid : in  std_logic;   -- one pulse per DESTUFFED payload bit
    bit_in    : in  std_logic;   -- the destuffed bit
    bus_idle  : in  std_logic;   -- '1' while the bus is idle/recessive

    -- ---- to the destuffer ----
    stuff_en  : out std_logic;   -- COMBINATIONAL: destuffing active

    -- ---- CRC interface ----
    crc_clr   : out std_logic;
    crc_en    : out std_logic;
    crc_bit   : out std_logic;
    crc_val   : in  std_logic_vector(14 downto 0);

    -- ---- decoded frame ----
    rx_id     : out std_logic_vector(10 downto 0);
    rx_rtr    : out std_logic;
    rx_ide    : out std_logic;
    rx_dlc    : out std_logic_vector(3 downto 0);
    rx_data   : out std_logic_vector(63 downto 0);

    -- ---- status ----
    rx_active : out std_logic;   -- high while decoding a frame
    rx_done   : out std_logic;   -- one pulse: frame complete and good
    crc_err   : out std_logic;   -- one pulse
    form_err  : out std_logic;   -- one pulse
    field_id  : out std_logic_vector(3 downto 0)
  );
end frame_rx;

architecture rtl of frame_rx is

  type state_t is (
    S_IDLE, S_SOF, S_ID, S_RTR, S_IDE, S_R0, S_DLC,
    S_DATA, S_CRC, S_CRCDEL, S_ACK, S_ACKDEL, S_EOF
  );
  signal state : state_t := S_IDLE;

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

  signal bitcnt : integer range 0 to 63 := 0;
  signal nbytes : integer range 0 to 8  := 0;

  signal id_r   : std_logic_vector(10 downto 0) := (others => '0');
  signal rtr_r  : std_logic := '0';
  signal ide_r  : std_logic := '0';
  signal dlc_r  : std_logic_vector(3 downto 0)  := (others => '0');
  signal data_r : std_logic_vector(63 downto 0) := (others => '0');

  -- CRC received off the wire, and the value computed locally,
  -- latched at the moment the data field ends
  signal crc_rx  : std_logic_vector(14 downto 0) := (others => '0');
  signal crc_exp : std_logic_vector(14 downto 0) := (others => '0');

  signal act_r    : std_logic := '0';
  signal done_r   : std_logic := '0';
  signal crcerr_r : std_logic := '0';
  signal formerr_r: std_logic := '0';
  signal cclr_r   : std_logic := '0';
  signal cen_r    : std_logic := '0';
  signal cbit_r   : std_logic := '0';
  signal field_r  : std_logic_vector(3 downto 0) := F_IDLE;

  -- a form error seen mid-frame, reported at the end
  signal form_seen : std_logic := '0';

begin

  -- ---------- COMBINATIONAL stuff enable ----------
  -- High from SOF through the last CRC bit. Must be valid DURING
  -- the slot, so it cannot be registered.
  stuff_en <= '1' when (state = S_SOF or state = S_ID
                        or state = S_RTR or state = S_IDE
                        or state = S_R0  or state = S_DLC
                        or state = S_DATA or state = S_CRC)
              else '0';

  process(clk, reset_n)
    variable dlc_full : std_logic_vector(3 downto 0);
  begin
    if reset_n = '0' then
      state     <= S_IDLE;
      bitcnt    <= 0;
      nbytes    <= 0;
      act_r     <= '0';
      done_r    <= '0';
      crcerr_r  <= '0';
      formerr_r <= '0';
      cclr_r    <= '0';
      cen_r     <= '0';
      cbit_r    <= '0';
      field_r   <= F_IDLE;
      form_seen <= '0';

    elsif rising_edge(clk) then
      -- one-cycle pulses
      done_r    <= '0';
      crcerr_r  <= '0';
      formerr_r <= '0';
      cclr_r    <= '0';
      cen_r     <= '0';

      case state is

        -- ================= IDLE =================
        when S_IDLE =>
          act_r   <= '0';
          field_r <= F_IDLE;
          -- SOF is the first DOMINANT bit after an idle bus
          if bit_valid = '1' and bit_in = '0' then
            cclr_r    <= '1';       -- start a fresh CRC
            cen_r     <= '1';       -- SOF is covered by the CRC
            cbit_r    <= '0';
            -- Clear the decoded fields at SOF. A remote frame (RTR=1)
            -- has NO data field, so without this the previous frame's
            -- data leaks into the current decode. Found on Day 28:
            -- an RTR frame reported the all-ones payload of the frame
            -- before it. Stale data across frames is a real hazard for
            -- anything consuming this output.
            data_r    <= (others => '0');
            id_r      <= (others => '0');
            dlc_r     <= (others => '0');
            act_r     <= '1';
            form_seen <= '0';
            bitcnt    <= 0;
            state     <= S_ID;
            field_r   <= F_SOF;
          end if;

        -- ================= IDENTIFIER =================
        when S_ID =>
          field_r <= F_ID;
          if bit_valid = '1' then
            id_r(10 - bitcnt) <= bit_in;
            cen_r  <= '1';
            cbit_r <= bit_in;
            if bitcnt = 10 then
              bitcnt <= 0;
              state  <= S_RTR;
            else
              bitcnt <= bitcnt + 1;
            end if;
          end if;

        when S_RTR =>
          field_r <= F_RTR;
          if bit_valid = '1' then
            rtr_r  <= bit_in;
            cen_r  <= '1';
            cbit_r <= bit_in;
            state  <= S_IDE;
          end if;

        when S_IDE =>
          field_r <= F_IDE;
          if bit_valid = '1' then
            ide_r  <= bit_in;
            cen_r  <= '1';
            cbit_r <= bit_in;
            state  <= S_R0;
          end if;

        when S_R0 =>
          field_r <= F_R0;
          if bit_valid = '1' then
            cen_r  <= '1';
            cbit_r <= bit_in;
            bitcnt <= 0;
            state  <= S_DLC;
          end if;

        -- ================= DLC =================
        when S_DLC =>
          field_r <= F_DLC;
          if bit_valid = '1' then
            dlc_r(3 - bitcnt) <= bit_in;
            cen_r  <= '1';
            cbit_r <= bit_in;
            if bitcnt = 3 then
              bitcnt <= 0;
              -- dlc_r is not fully updated yet this cycle, so
              -- rebuild the value including the bit just seen
              if rtr_r = '1' then
                nbytes <= 0;             -- remote frame: no data
                state  <= S_CRC;
              else
                -- NOTE: dlc_r has not taken the fourth bit yet in
                -- this clock, so rebuild the value including the bit
                -- just received. A case expression must have a
                -- locally static subtype in VHDL-93, so the
                -- concatenation goes into a variable first.
                dlc_full := dlc_r(3 downto 1) & bit_in;
                if dlc_full = "0000" then
                  nbytes <= 0; state <= S_CRC;
                elsif unsigned(dlc_full) > 8 then
                  nbytes <= 8; state <= S_DATA;
                else
                  nbytes <= to_integer(unsigned(dlc_full));
                  state  <= S_DATA;
                end if;
              end if;
            else
              bitcnt <= bitcnt + 1;
            end if;
          end if;

        -- ================= DATA =================
        when S_DATA =>
          field_r <= F_DATA;
          if bit_valid = '1' then
            data_r(63 - bitcnt) <= bit_in;
            cen_r  <= '1';
            cbit_r <= bit_in;
            if bitcnt = (nbytes * 8) - 1 then
              bitcnt <= 0;
              state  <= S_CRC;
            else
              bitcnt <= bitcnt + 1;
            end if;
          end if;

        -- ================= CRC SEQUENCE =================
        when S_CRC =>
          field_r <= F_CRC;
          if bit_valid = '1' then
            -- latch the locally computed CRC on the first CRC bit,
            -- before any more bits disturb it
            if bitcnt = 0 then
              crc_exp <= crc_val;
            end if;
            crc_rx(14 - bitcnt) <= bit_in;
            -- crc_en NOT asserted: the CRC does not cover itself
            if bitcnt = 14 then
              bitcnt <= 0;
              state  <= S_CRCDEL;
            else
              bitcnt <= bitcnt + 1;
            end if;
          end if;

        -- ================= FIXED-FORM FIELDS =================
        when S_CRCDEL =>
          field_r <= F_CRCDEL;
          if bit_valid = '1' then
            if bit_in = '0' then
              form_seen <= '1';      -- must be recessive
            end if;
            state <= S_ACK;
          end if;

        when S_ACK =>
          field_r <= F_ACK;
          if bit_valid = '1' then
            -- either level is legal here: a receiver that accepted
            -- the frame drives dominant, otherwise it stays
            -- recessive. No form check.
            state <= S_ACKDEL;
          end if;

        when S_ACKDEL =>
          field_r <= F_ACKDEL;
          if bit_valid = '1' then
            if bit_in = '0' then
              form_seen <= '1';
            end if;
            bitcnt <= 0;
            state  <= S_EOF;
          end if;

        when S_EOF =>
          field_r <= F_EOF;
          if bit_valid = '1' then
            if bit_in = '0' then
              form_seen <= '1';
            end if;
            if bitcnt = 6 then       -- 7 bits
              bitcnt <= 0;
              act_r  <= '0';
              state  <= S_IDLE;
              -- ---- report the outcome ----
              if form_seen = '1' or bit_in = '0' then
                formerr_r <= '1';
              elsif crc_rx /= crc_exp then
                crcerr_r  <= '1';
              else
                done_r    <= '1';
              end if;
            else
              bitcnt <= bitcnt + 1;
            end if;
          end if;

        when others =>
          state <= S_IDLE;

      end case;
    end if;
  end process;

  crc_clr   <= cclr_r;
  crc_en    <= cen_r;
  crc_bit   <= cbit_r;

  rx_id     <= id_r;
  rx_rtr    <= rtr_r;
  rx_ide    <= ide_r;
  rx_dlc    <= dlc_r;
  rx_data   <= data_r;

  rx_active <= act_r;
  rx_done   <= done_r;
  crc_err   <= crcerr_r;
  form_err  <= formerr_r;
  field_id  <= field_r;

end rtl;
