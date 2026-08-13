library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity bit_stuff is
  generic (
    STUFF_LEN : integer := 5
  );
  port (
    clk        : in  std_logic;
    reset_n    : in  std_logic;
    tx_en      : in  std_logic;
    tx_bit_in  : in  std_logic;
    tx_stuff_en: in  std_logic;
    tx_bit_out : out std_logic;
    tx_stall   : out std_logic;
    tx_stall_c : out std_logic;
    rx_en      : in  std_logic;
    rx_bit_in  : in  std_logic;
    rx_stuff_en: in  std_logic;
    rx_bit_out : out std_logic;
    rx_valid   : out std_logic;
    rx_discard : out std_logic;
    stuff_err  : out std_logic
  );
end bit_stuff;
architecture rtl of bit_stuff is
  signal tx_same_cnt : integer range 1 to 8 := 1;
  signal tx_last     : std_logic := '1';
  signal tx_started  : std_logic := '0';
  signal tx_out_r    : std_logic := '1';
  signal tx_stall_r  : std_logic := '0';
  signal rx_same_cnt : integer range 1 to 8 := 1;
  signal rx_last     : std_logic := '1';
  signal rx_started  : std_logic := '0';
  signal rx_out_r    : std_logic := '1';
  signal rx_valid_r  : std_logic := '0';
  signal rx_disc_r   : std_logic := '0';
  signal stuff_err_r : std_logic := '0';
begin
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
          tx_out_r    <= not tx_last;
          tx_stall_r  <= '1';
          tx_last     <= not tx_last;
          tx_same_cnt <= 1;
        else
          tx_out_r   <= tx_bit_in;
          tx_started <= '1';
          if tx_stuff_en = '0' then
            tx_same_cnt <= 1;
          elsif tx_started = '1' and tx_bit_in = tx_last then
            if tx_same_cnt < STUFF_LEN then
              tx_same_cnt <= tx_same_cnt + 1;
            end if;
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
  tx_stall_c <= '1' when (tx_stuff_en = '1' and tx_started = '1'
                          and tx_same_cnt >= STUFF_LEN)
                else '0';
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
          if rx_bit_in = rx_last then
            stuff_err_r <= '1';
            if rx_same_cnt < STUFF_LEN + 1 then
              rx_same_cnt <= rx_same_cnt + 1;
            end if;
            rx_last     <= rx_bit_in;
          else
            rx_disc_r   <= '1';
            rx_last     <= rx_bit_in;
            rx_same_cnt <= 1;
          end if;
        else
          rx_out_r   <= rx_bit_in;
          rx_valid_r <= '1';
          rx_started <= '1';
          if rx_stuff_en = '0' then
            rx_same_cnt <= 1;
          elsif rx_started = '1' and rx_bit_in = rx_last then
            if rx_same_cnt < STUFF_LEN + 1 then
              rx_same_cnt <= rx_same_cnt + 1;
            end if;
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
