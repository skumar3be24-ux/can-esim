library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity error_mgmt is
  generic (
    PASSIVE_LIMIT : integer := 128;
    BUSOFF_LIMIT  : integer := 256;
    RECOVERY_CNT  : integer := 128
  );
  port (
    clk        : in  std_logic;
    reset_n    : in  std_logic;
    tx_error   : in  std_logic;
    rx_error   : in  std_logic;
    rx_err_big : in  std_logic;
    tx_success : in  std_logic;
    rx_success : in  std_logic;
    idle_11    : in  std_logic;
    tec        : out std_logic_vector(8 downto 0);
    rec        : out std_logic_vector(8 downto 0);
    err_active : out std_logic;
    err_passive: out std_logic;
    bus_off    : out std_logic
  );
end error_mgmt;
architecture rtl of error_mgmt is
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
        if tx_error = '1' then
          t := t + 8;
        elsif tx_success = '1' then
          if t > 0 then
            t := t - 1;
          end if;
        end if;
        if rx_err_big = '1' then
          r := r + 8;
        elsif rx_error = '1' then
          r := r + 1;
        elsif rx_success = '1' then
          if r > 127 then
            r := 127;
          elsif r > 0 then
            r := r - 1;
          end if;
        end if;
        if t < 0 then t := 0; end if;
        if r < 0 then r := 0; end if;
        if t > 511 then t := 511; end if;
        if r > 511 then r := 511; end if;
        tec_r <= t;
        rec_r <= r;
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
