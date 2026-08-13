-- ============================================================
-- CAN bit stuffing / destuffing
-- Day 23, Phase 3
--
-- RULE (ISO 11898-1):
--   After FIVE consecutive bits of identical polarity the
--   transmitter inserts ONE bit of the opposite polarity.
--   The receiver detects the same run and DISCARDS the next bit.
--
-- WHY IT EXISTS:
--   CAN has no clock line. Receivers resynchronise on
--   recessive->dominant edges (see bit_timing.vhdl, Day 22).
--   Without stuffing, a long run of identical bits would give the
--   receiver no edge to lock onto and the two oscillators would
--   drift apart. Stuffing guarantees an edge at least every SIX
--   bit times, which bounds the accumulated phase error.
--
-- SCOPE - this is where implementations commonly go wrong:
--   Stuffing applies from SOF through the CRC SEQUENCE only.
--   It does NOT apply to:
--     CRC delimiter, ACK slot, ACK delimiter, EOF, interframe
--   Those are fixed-form fields. A stuffed bit there would be a
--   protocol violation. This module therefore takes an explicit
--   stuff_en input rather than guessing.
--
-- THE COUNTER
--   same_cnt counts consecutive identical bits, starting at 1 for
--   the first bit of a run. When it reaches 5 the next bit is a
--   stuff bit. A stuffed bit RESETS the count to 1, because the
--   stuffed bit itself is the first bit of the next run.
--   Off-by-one here means stuffing after 4 or 6 bits - both wrong.
--
-- ERROR CONDITION
--   SIX identical bits on the bus is a STUFF ERROR. This is not
--   an edge case: error frames are deliberately six dominant
--   bits, so the destuffer MUST report it rather than silently
--   resynchronise. stuff_err is a one-cycle pulse.
--
-- INTERFACE
--   This module is bit-clocked, not tq-clocked. It expects one
--   enable pulse per bit (from bit_timing's sample_pt for the
--   receive path, or the transmit bit clock for the send path).
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bit_stuff is
  generic (
    STUFF_LEN : integer := 5    -- stuff after this many identical bits
  );
  port (
    clk        : in  std_logic;
    reset_n    : in  std_logic;

    -- ---------------- transmit side ----------------
    tx_en      : in  std_logic;  -- one pulse per bit slot
    tx_bit_in  : in  std_logic;  -- next payload bit
    tx_stuff_en: in  std_logic;  -- stuffing active for this field
    tx_bit_out : out std_logic;  -- bit to drive on the bus
    tx_stall   : out std_logic;  -- '1' = a stuff bit is being sent,
                                 --       payload bit NOT consumed

    -- ---------------- receive side -----------------
    rx_en      : in  std_logic;  -- one pulse per sampled bit
    rx_bit_in  : in  std_logic;  -- bit sampled from the bus
    rx_stuff_en: in  std_logic;  -- destuffing active for this field
    rx_bit_out : out std_logic;  -- destuffed payload bit
    rx_valid   : out std_logic;  -- '1' = rx_bit_out is real payload
    rx_discard : out std_logic;  -- '1' = this bit was a stuff bit
    stuff_err  : out std_logic   -- '1' = six identical bits seen
  );
end bit_stuff;

architecture rtl of bit_stuff is

  -- ---- transmit state ----
  signal tx_same_cnt : integer range 1 to 8 := 1;
  signal tx_last     : std_logic := '1';
  signal tx_started  : std_logic := '0';   -- has any bit been sent
  signal tx_out_r    : std_logic := '1';
  signal tx_stall_r  : std_logic := '0';

  -- ---- receive state ----
  signal rx_same_cnt : integer range 1 to 8 := 1;
  signal rx_last     : std_logic := '1';
  signal rx_started  : std_logic := '0';
  signal rx_out_r    : std_logic := '1';
  signal rx_valid_r  : std_logic := '0';
  signal rx_disc_r   : std_logic := '0';
  signal stuff_err_r : std_logic := '0';

begin

  -- ============================================================
  -- TRANSMIT: insert a stuff bit after STUFF_LEN identical bits
  -- ============================================================
  tx_proc : process(clk, reset_n)
    variable stuff_now : boolean;
  begin
    if reset_n = '0' then
      tx_same_cnt <= 1;
      tx_last     <= '1';
      tx_started  <= '0';
      tx_out_r    <= '1';
      tx_stall_r  <= '0';

    elsif rising_edge(clk) then
      tx_stall_r <= '0';

      if tx_en = '1' then

        stuff_now := (tx_stuff_en = '1')
                 and (tx_started = '1')
                 and (tx_same_cnt >= STUFF_LEN);

        if stuff_now then
          -- ---- send the stuff bit: opposite of the run ----
          -- The payload bit is NOT consumed this slot; tx_stall
          -- tells the shift register to hold.
          tx_out_r    <= not tx_last;
          tx_stall_r  <= '1';
          -- the stuff bit starts a new run of length 1
          tx_last     <= not tx_last;
          tx_same_cnt <= 1;

        else
          -- ---- send the payload bit ----
          tx_out_r   <= tx_bit_in;
          tx_started <= '1';

          if tx_started = '1' and tx_bit_in = tx_last then
            tx_same_cnt <= tx_same_cnt + 1;
          else
            tx_same_cnt <= 1;
          end if;
          tx_last <= tx_bit_in;
        end if;

      end if;
    end if;
  end process;

  tx_bit_out <= tx_out_r;
  tx_stall   <= tx_stall_r;

  -- ============================================================
  -- RECEIVE: discard a stuff bit after STUFF_LEN identical bits,
  --          and flag STUFF_LEN+1 identical bits as an error
  -- ============================================================
  rx_proc : process(clk, reset_n)
    variable expect_stuff : boolean;
  begin
    if reset_n = '0' then
      rx_same_cnt <= 1;
      rx_last     <= '1';
      rx_started  <= '0';
      rx_out_r    <= '1';
      rx_valid_r  <= '0';
      rx_disc_r   <= '0';
      stuff_err_r <= '0';

    elsif rising_edge(clk) then
      rx_valid_r  <= '0';
      rx_disc_r   <= '0';
      stuff_err_r <= '0';

      if rx_en = '1' then

        expect_stuff := (rx_stuff_en = '1')
                    and (rx_started = '1')
                    and (rx_same_cnt >= STUFF_LEN);

        if expect_stuff then
          -- this bit MUST be the opposite of the run
          if rx_bit_in = rx_last then
            -- six identical bits -> STUFF ERROR
            stuff_err_r <= '1';
            rx_same_cnt <= rx_same_cnt + 1;
            rx_last     <= rx_bit_in;
          else
            -- correct stuff bit: discard it, start a new run
            rx_disc_r   <= '1';
            rx_last     <= rx_bit_in;
            rx_same_cnt <= 1;
          end if;

        else
          -- ---- normal payload bit ----
          rx_out_r   <= rx_bit_in;
          rx_valid_r <= '1';
          rx_started <= '1';

          if rx_started = '1' and rx_bit_in = rx_last then
            rx_same_cnt <= rx_same_cnt + 1;
          else
            rx_same_cnt <= 1;
          end if;
          rx_last <= rx_bit_in;
        end if;

      end if;
    end if;
  end process;

  rx_bit_out <= rx_out_r;
  rx_valid   <= rx_valid_r;
  rx_discard <= rx_disc_r;
  stuff_err  <= stuff_err_r;

end rtl;
