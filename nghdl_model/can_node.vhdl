library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity can_node is
  generic (
    SYNC_SEG   : integer := 1;
    PROP_SEG   : integer := 5;
    PHASE_SEG1 : integer := 6;
    PHASE_SEG2 : integer := 4;
    SJW        : integer := 4
  );
  port (
    clk       : in  std_logic;
    reset_n   : in  std_logic;
    can_rx    : in  std_logic;
    can_tx    : out std_logic;
    tx_req    : in  std_logic;
    tx_id     : in  std_logic_vector(10 downto 0);
    tx_rtr    : in  std_logic;
    tx_dlc    : in  std_logic_vector(3 downto 0);
    tx_data   : in  std_logic_vector(63 downto 0);
    tx_busy   : out std_logic;
    tx_done   : out std_logic;
    tx_arblost: out std_logic;
    tx_noack  : out std_logic;
    rx_valid  : out std_logic;
    rx_id     : out std_logic_vector(10 downto 0);
    rx_rtr    : out std_logic;
    rx_dlc    : out std_logic_vector(3 downto 0);
    rx_data   : out std_logic_vector(63 downto 0);
    rx_crcerr : out std_logic;
    rx_formerr: out std_logic;
    rx_stuferr: out std_logic
  );
end can_node;
architecture rtl of can_node is
  signal tx_bit_out : std_logic;
  signal tx_active  : std_logic;
  signal tx_field   : std_logic_vector(3 downto 0);
  signal bit_slot   : std_logic;
  signal sample_now : std_logic;
  signal stuff_now  : std_logic;
  signal arb_lost_s : std_logic;
  signal ack_ok_s   : std_logic;
  signal ack_err_s  : std_logic;
  signal rxs_en       : std_logic;
  signal rxs_stuff_en : std_logic;
  signal rxs_bit_out  : std_logic;
  signal rxs_valid    : std_logic;
  signal rxs_discard  : std_logic;
  signal rxs_stuff_err: std_logic;
  signal rxs_tx_bo, rxs_tx_st, rxs_tx_stc : std_logic;
  signal rcrc_clr, rcrc_en, rcrc_bit : std_logic;
  signal rcrc_val : std_logic_vector(14 downto 0);
  signal ack_drive_raw : std_logic;
  signal ack_drive_eff : std_logic;
  signal rx_done_s : std_logic;
begin
  u_tx : entity work.can_tx_path
    generic map (
      SYNC_SEG => SYNC_SEG, PROP_SEG => PROP_SEG,
      PHASE_SEG1 => PHASE_SEG1, PHASE_SEG2 => PHASE_SEG2,
      SJW => SJW
    )
    port map (
      clk => clk, reset_n => reset_n,
      frame_start => tx_req,
      id_in   => tx_id,
      rtr_in  => tx_rtr,
      dlc_in  => tx_dlc,
      data_in => tx_data,
      can_rx  => can_rx,
      can_tx  => tx_bit_out,
      frame_active => tx_active,
      field_id => tx_field,
      bit_slot => bit_slot,
      sample_now => sample_now,
      stuff_now => stuff_now,
      arb_lost => arb_lost_s,
      ack_ok => ack_ok_s,
      ack_err => ack_err_s
    );
  rxs_en <= sample_now;
  u_rxstuff : entity work.bit_stuff
    generic map (STUFF_LEN => 5)
    port map (
      clk => clk, reset_n => reset_n,
      tx_en => '0', tx_bit_in => '1', tx_stuff_en => '0',
      tx_bit_out => rxs_tx_bo,
      tx_stall   => rxs_tx_st,
      tx_stall_c => rxs_tx_stc,
      rx_en       => rxs_en,
      rx_bit_in   => can_rx,
      rx_stuff_en => rxs_stuff_en,
      rx_bit_out  => rxs_bit_out,
      rx_valid    => rxs_valid,
      rx_discard  => rxs_discard,
      stuff_err   => rxs_stuff_err
    );
  u_rxdec : entity work.frame_rx
    port map (
      clk => clk, reset_n => reset_n,
      bit_valid => rxs_valid,
      bit_in    => rxs_bit_out,
      bus_idle  => '0',
      stuff_en  => rxs_stuff_en,
      crc_clr => rcrc_clr, crc_en => rcrc_en,
      crc_bit => rcrc_bit, crc_val => rcrc_val,
      rx_id => rx_id, rx_rtr => rx_rtr, rx_ide => open,
      rx_dlc => rx_dlc, rx_data => rx_data,
      ack_drive => ack_drive_raw,
      rx_active => open,
      rx_done   => rx_done_s,
      crc_err   => rx_crcerr,
      form_err  => rx_formerr,
      field_id  => open
    );
  u_rxcrc : entity work.crc15
    port map (
      clk => clk, reset_n => reset_n,
      crc_clr => rcrc_clr, crc_en => rcrc_en,
      crc_in => rcrc_bit, crc_out => rcrc_val
    );
  ack_drive_eff <= ack_drive_raw and (not tx_active);
  can_tx <= tx_bit_out and (not ack_drive_eff);
  tx_busy    <= tx_active;
  tx_done    <= ack_ok_s;
  tx_arblost <= arb_lost_s;
  tx_noack   <= ack_err_s;
  rx_valid   <= rx_done_s;
  rx_stuferr <= rxs_stuff_err;
end rtl;
