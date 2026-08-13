library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity can_node_top is
port(clk : in std_logic;
     reset_n : in std_logic;
     can_rx : in std_logic;
     tx_req : in std_logic;
     id_sel : in std_logic_vector(1 downto 0);
     can_tx : out std_logic;
     tx_busy : out std_logic;
     tx_done : out std_logic;
     arb_lost : out std_logic;
     rx_valid : out std_logic;
     err_frame : out std_logic;
     bus_off : out std_logic);
end can_node_top;
architecture rtl of can_node_top is
  signal sel_id   : std_logic_vector(10 downto 0);
  signal sel_data : std_logic_vector(63 downto 0);
  signal n_tx_busy    : std_logic;
  signal n_tx_done    : std_logic;
  signal n_tx_arblost : std_logic;
  signal n_tx_noack   : std_logic;
  signal n_rx_valid   : std_logic;
  signal n_err_frame  : std_logic;
  signal n_bus_off    : std_logic;
begin
  sel_id <= "00010100101" when id_sel = "00" else
            "00100100011" when id_sel = "01" else
            "01010101010" when id_sel = "10" else
            "10101010101";
  sel_data <= x"A500000000000000" when id_sel = "00" else
              x"3C00000000000000" when id_sel = "01" else
              x"7700000000000000" when id_sel = "10" else
              x"E100000000000000";
  u_node : entity work.can_node
    generic map (
      SYNC_SEG   => 1,
      PROP_SEG   => 5,
      PHASE_SEG1 => 6,
      PHASE_SEG2 => 4,
      SJW        => 4
    )
    port map (
      clk => clk,
      reset_n => reset_n,
      can_rx => can_rx,
      can_tx => can_tx,
      tx_req => tx_req,
      tx_id => sel_id,
      tx_rtr => '0',
      tx_dlc => "0001",
      tx_data => sel_data,
      tx_busy => n_tx_busy,
      tx_done => n_tx_done,
      tx_arblost => n_tx_arblost,
      tx_noack => n_tx_noack,
      rx_valid => n_rx_valid,
      rx_id => open,
      rx_rtr => open,
      rx_dlc => open,
      rx_data => open,
      rx_crcerr => open,
      rx_formerr => open,
      rx_stuferr => open,
      tec_out => open,
      rec_out => open,
      err_active => open,
      err_passive => open,
      bus_off => n_bus_off,
      err_frame => n_err_frame
    );
  tx_busy  <= n_tx_busy;
  tx_done  <= n_tx_done;
  arb_lost <= n_tx_arblost;
  rx_valid <= n_rx_valid;
  err_frame <= n_err_frame;
  bus_off <= n_bus_off;
end rtl;
