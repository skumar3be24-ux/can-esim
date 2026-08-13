library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity error_gen is
  generic (
    FLAG_LEN  : integer := 6;
    DELIM_LEN : integer := 8;
    MAX_WAIT  : integer := 6
  );
  port (
    clk        : in  std_logic;
    reset_n    : in  std_logic;
    bit_en     : in  std_logic;
    bus_bit    : in  std_logic;
    err_req    : in  std_logic;
    is_passive : in  std_logic;
    err_active : out std_logic;
    err_bit    : out std_logic;
    err_done   : out std_logic;
    stuck_bus  : out std_logic
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
            passive_r <= is_passive;
            act_r     <= '1';
            cnt       <= 0;
            waitcnt   <= 0;
            state     <= E_FLAG;
          end if;
        when E_FLAG =>
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
          bit_r <= '1';
          if bit_en = '1' then
            if bus_bit = '1' then
              waitcnt <= 0;
              cnt     <= 0;
              state   <= E_DELIM;
            elsif waitcnt >= MAX_WAIT - 1 then
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
