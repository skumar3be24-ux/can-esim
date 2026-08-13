-- ============================================================
-- CAN error frame generator
-- Day 34, Phase 5
--
-- An error frame is 6 bits of ERROR FLAG followed by 8 bits of
-- ERROR DELIMITER (recessive).
--
-- ERROR ACTIVE node -> 6 DOMINANT bits
--   Six identical bits deliberately violate the stuffing rule
--   (maximum five). Every other node therefore detects a stuff
--   error and sends its own error flag. That is the entire
--   propagation mechanism: a node destroys a frame by triggering
--   everyone else's stuff-error detector.
--
--   This is the same detector built in bit_stuff on Day 23 - the
--   error frame and the stuff-error check are two halves of one
--   design.
--
-- ERROR PASSIVE node -> 6 RECESSIVE bits
--   Recessive contributes nothing to a wired-AND bus, so a
--   degraded node signals its unhappiness without disrupting
--   traffic. This is the whole point of fault confinement: the
--   node is progressively muted, not silenced.
--
-- SUPERPOSITION - why the delimiter cannot simply be counted
--   Other nodes detect the error one bit later than the node that
--   started it, so their flags begin later and the combined
--   dominant sequence can run to 12 bits. After sending its own
--   six, a node must WAIT FOR THE BUS TO GO RECESSIVE before
--   starting the delimiter. Counting a fixed 6 then 8 would put
--   the delimiter in the middle of someone else's flag.
--
--   ISO 11898-1 bounds the wait: a node that still sees dominant
--   after 6 extra bits has a stuck bus, which is a separate fault.
--
-- SEQUENCE
--   FLAG   6 bits, dominant if error-active, recessive if passive
--   WAIT   monitor until the bus is recessive (bounded)
--   DELIM  8 recessive bits
--   then normal interframe space resumes
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity error_gen is
  generic (
    FLAG_LEN  : integer := 6;
    DELIM_LEN : integer := 8;
    MAX_WAIT  : integer := 6    -- bounded superposition allowance
  );
  port (
    clk        : in  std_logic;
    reset_n    : in  std_logic;

    bit_en     : in  std_logic;  -- one pulse per bit slot
    bus_bit    : in  std_logic;  -- current bus level, sampled

    err_req    : in  std_logic;  -- pulse: start an error frame
    is_passive : in  std_logic;  -- '1' = error-passive node

    err_active : out std_logic;  -- high for the whole error frame
    err_bit    : out std_logic;  -- bit to drive on the bus
    err_done   : out std_logic;  -- pulse: error frame complete
    stuck_bus  : out std_logic   -- pulse: bus never went recessive
  );
end error_gen;

architecture rtl of error_gen is

  type state_t is (E_IDLE, E_FLAG, E_WAIT, E_DELIM);
  signal state : state_t := E_IDLE;

  signal cnt      : integer range 0 to 15 := 0;
  signal waitcnt  : integer range 0 to 15 := 0;

  signal act_r    : std_logic := '0';
  signal bit_r    : std_logic := '1';
  signal done_r   : std_logic := '0';
  signal stuck_r  : std_logic := '0';

  -- latched at the start so a mid-frame change of fault state
  -- cannot switch the flag polarity halfway through
  signal passive_r : std_logic := '0';

begin

  process(clk, reset_n)
  begin
    if reset_n = '0' then
      state     <= E_IDLE;
      cnt       <= 0;
      waitcnt   <= 0;
      act_r     <= '0';
      bit_r     <= '1';
      done_r    <= '0';
      stuck_r   <= '0';
      passive_r <= '0';

    elsif rising_edge(clk) then
      done_r  <= '0';
      stuck_r <= '0';

      case state is

        when E_IDLE =>
          act_r <= '0';
          bit_r <= '1';
          if err_req = '1' then
            -- latch the fault state now: the flag polarity must
            -- not change partway through
            passive_r <= is_passive;
            act_r     <= '1';
            cnt       <= 0;
            waitcnt   <= 0;
            state     <= E_FLAG;
          end if;

        when E_FLAG =>
          -- dominant if error-active, recessive if error-passive
          if passive_r = '1' then
            bit_r <= '1';
          else
            bit_r <= '0';
          end if;
          if bit_en = '1' then
            if cnt = FLAG_LEN - 1 then
              cnt   <= 0;
              state <= E_WAIT;
            else
              cnt <= cnt + 1;
            end if;
          end if;

        when E_WAIT =>
          -- Our own flag is done. Release to recessive and wait
          -- for the bus itself to go recessive - other nodes may
          -- still be driving their flags, and the superposed
          -- sequence can reach 12 bits.
          bit_r <= '1';
          if bit_en = '1' then
            if bus_bit = '1' then
              waitcnt <= 0;
              cnt     <= 0;
              state   <= E_DELIM;
            elsif waitcnt >= MAX_WAIT - 1 then
              -- still dominant after the allowance: the bus is
              -- stuck, which is a different fault entirely
              stuck_r <= '1';
              waitcnt <= 0;
              cnt     <= 0;
              state   <= E_DELIM;
            else
              waitcnt <= waitcnt + 1;
            end if;
          end if;

        when E_DELIM =>
          bit_r <= '1';
          if bit_en = '1' then
            if cnt = DELIM_LEN - 1 then
              cnt    <= 0;
              act_r  <= '0';
              done_r <= '1';
              state  <= E_IDLE;
            else
              cnt <= cnt + 1;
            end if;
          end if;

        when others =>
          state <= E_IDLE;

      end case;
    end if;
  end process;

  err_active <= act_r;
  err_bit    <= bit_r;
  err_done   <= done_r;
  stuck_bus  <= stuck_r;

end rtl;
