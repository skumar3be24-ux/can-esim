-- ============================================================
-- CAN error management - fault confinement
-- Day 33, Phase 5
--
-- Two counters decide how much a node is allowed to disturb the
-- bus. A node that keeps causing errors is progressively muted,
-- then disconnected. This is what stops one broken node from
-- taking down an entire network.
--
-- COUNTER RULES (ISO 11898-1)
--
--   event                                        TEC    REC
--   ------------------------------------------   ----   ----
--   receiver detects an error                      -     +1
--   receiver detects a bit error while sending
--     an active error flag                         -     +8
--   transmitter detects an error                  +8      -
--   successful transmission                       -1      -
--   successful reception                           -      -1
--
-- THE ASYMMETRY IS THE WHOLE DESIGN
--   +8 for causing an error, -1 for success. A node must succeed
--   EIGHT times to undo one failure, so a genuinely faulty node
--   degrades fast while occasional noise is forgiven slowly.
--
-- STATES
--   ERROR ACTIVE   TEC < 128 and REC < 128
--                  Sends DOMINANT error flags: actively destroys
--                  a frame it believes is bad, forcing everyone
--                  to discard it.
--   ERROR PASSIVE  TEC >= 128 or REC >= 128
--                  Sends RECESSIVE error flags, which do not
--                  disturb the bus. A degraded node stops
--                  shouting but keeps listening.
--   BUS OFF        TEC >= 256
--                  Disconnects completely. Recovery requires 128
--                  occurrences of 11 consecutive recessive bits,
--                  i.e. the bus must be quiet for a long time.
--
-- DECREMENT RULES - easy to get wrong
--   TEC and REC never go below 0.
--   REC decrements to 0 normally, BUT if REC > 127 a successful
--   reception sets it to a value between 119 and 127 rather than
--   decrementing by 1. We use 127, which is the common choice.
--   TEC does not decrement while bus-off.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity error_mgmt is
  generic (
    PASSIVE_LIMIT : integer := 128;
    BUSOFF_LIMIT  : integer := 256;
    RECOVERY_CNT  : integer := 128   -- 11-bit recessive sequences
  );
  port (
    clk        : in  std_logic;
    reset_n    : in  std_logic;

    -- ---- error events (one-cycle pulses) ----
    tx_error   : in  std_logic;  -- transmitter detected an error
    rx_error   : in  std_logic;  -- receiver detected an error
    rx_err_big : in  std_logic;  -- receiver error worth +8
    tx_success : in  std_logic;  -- frame transmitted and acked
    rx_success : in  std_logic;  -- frame received cleanly

    -- ---- bus-off recovery ----
    idle_11    : in  std_logic;  -- pulse: 11 recessive bits seen

    -- ---- status ----
    tec        : out std_logic_vector(8 downto 0);
    rec        : out std_logic_vector(8 downto 0);
    err_active : out std_logic;
    err_passive: out std_logic;
    bus_off    : out std_logic
  );
end error_mgmt;

architecture rtl of error_mgmt is

  -- 0..511 so bus-off (256) is representable with headroom
  signal tec_r : integer range 0 to 511 := 0;
  signal rec_r : integer range 0 to 511 := 0;

  signal busoff_r : std_logic := '0';
  signal recov_r  : integer range 0 to 255 := 0;

begin

  process(clk, reset_n)
    variable t : integer range -16 to 527;
    variable r : integer range -16 to 527;
  begin
    if reset_n = '0' then
      tec_r    <= 0;
      rec_r    <= 0;
      busoff_r <= '0';
      recov_r  <= 0;

    elsif rising_edge(clk) then

      if busoff_r = '1' then
        -- ---------- BUS OFF: only recovery matters ----------
        -- The node is disconnected. It counts quiet periods and
        -- rejoins after RECOVERY_CNT of them, with both counters
        -- cleared.
        if idle_11 = '1' then
          if recov_r >= RECOVERY_CNT - 1 then
            busoff_r <= '0';
            recov_r  <= 0;
            tec_r    <= 0;
            rec_r    <= 0;
          else
            recov_r <= recov_r + 1;
          end if;
        end if;

      else
        t := tec_r;
        r := rec_r;

        -- ---------- transmit side ----------
        if tx_error = '1' then
          t := t + 8;
        elsif tx_success = '1' then
          if t > 0 then
            t := t - 1;
          end if;
        end if;

        -- ---------- receive side ----------
        if rx_err_big = '1' then
          r := r + 8;
        elsif rx_error = '1' then
          r := r + 1;
        elsif rx_success = '1' then
          if r > 127 then
            -- above 127 a good frame resets into the 119..127
            -- band rather than decrementing by one
            r := 127;
          elsif r > 0 then
            r := r - 1;
          end if;
        end if;

        -- ---------- clamp and commit ----------
        if t < 0 then t := 0; end if;
        if r < 0 then r := 0; end if;
        if t > 511 then t := 511; end if;
        if r > 511 then r := 511; end if;

        tec_r <= t;
        rec_r <= r;

        -- ---------- bus-off entry ----------
        if t >= BUSOFF_LIMIT then
          busoff_r <= '1';
          recov_r  <= 0;
        end if;

      end if;
    end if;
  end process;

  tec <= std_logic_vector(to_unsigned(tec_r, 9));
  rec <= std_logic_vector(to_unsigned(rec_r, 9));

  bus_off     <= busoff_r;
  err_passive <= '1' when (busoff_r = '0'
                           and (tec_r >= PASSIVE_LIMIT
                                or rec_r >= PASSIVE_LIMIT))
                 else '0';
  err_active  <= '1' when (busoff_r = '0'
                           and tec_r < PASSIVE_LIMIT
                           and rec_r < PASSIVE_LIMIT)
                 else '0';

end rtl;
