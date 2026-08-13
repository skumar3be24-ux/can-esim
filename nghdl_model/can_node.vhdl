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
    rx_stuferr: out std_logic;
    tec_out    : out std_logic_vector(8 downto 0);
    rec_out    : out std_logic_vector(8 downto 0);
    err_active : out std_logic;
    err_passive: out std_logic;
    bus_off    : out std_logic;
    err_frame  : out std_logic
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
  signal rx_crc_s   : std_logic;
  signal rx_form_s  : std_logic;
  signal any_rx_err : std_logic;
  signal err_req_s  : std_logic;
  signal eg_active : std_logic;
  signal eg_bit    : std_logic;
  signal eg_done   : std_logic;
  signal eg_stuck  : std_logic;
  signal em_active  : std_logic;
  signal em_passive : std_logic;
  signal em_busoff  : std_logic;
  signal bus_sampled : std_logic := '1';
  signal rec_run  : integer range 0 to 15 := 0;
  signal idle11_s : std_logic := '0';
  signal node_tx    : std_logic;
  signal bit_err_s  : std_logic;
  signal in_ack_s   : std_logic;
  signal tx_err_any : std_logic;
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
      bit_err     => bit_err_s,
      in_ack_slot => in_ack_s,
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
      crc_err   => rx_crc_s,
      form_err  => rx_form_s,
      field_id  => open
    );
  u_rxcrc : entity work.crc15
    port map (
      clk => clk, reset_n => reset_n,
      crc_clr => rcrc_clr, crc_en => rcrc_en,
      crc_in => rcrc_bit, crc_out => rcrc_val
    );
  in_ack_s <= '1' when (tx_field = x"9" or tx_field = x"A"
                        or tx_field = x"B") else '0';
  any_rx_err <= (rx_crc_s or rx_form_s or rxs_stuff_err)
                and (not eg_active);
  tx_err_any <= (bit_err_s or ack_err_s) and (not eg_active);
  err_req_s  <= any_rx_err or tx_err_any;
  process(clk, reset_n)
  begin
    if reset_n = '0' then
      bus_sampled <= '1';
      rec_run     <= 0;
      idle11_s    <= '0';
    elsif rising_edge(clk) then
      idle11_s <= '0';
      if sample_now = '1' then
        bus_sampled <= can_rx;
        if can_rx = '1' then
          if rec_run >= 10 then
            idle11_s <= '1';
            rec_run  <= 0;
          else
            rec_run <= rec_run + 1;
          end if;
        else
          rec_run <= 0;
        end if;
      end if;
    end if;
  end process;
  u_errgen : entity work.error_gen
    port map (
      clk => clk, reset_n => reset_n,
      bit_en     => bit_slot,
      bus_bit    => bus_sampled,
      err_req    => err_req_s,
      is_passive => em_passive,
      err_active => eg_active,
      err_bit    => eg_bit,
      err_done   => eg_done,
      stuck_bus  => eg_stuck
    );
  u_errmgmt : entity work.error_mgmt
    port map (
      clk => clk, reset_n => reset_n,
      tx_error   => tx_err_any,
      rx_error   => any_rx_err,
      rx_err_big => '0',
      tx_success => ack_ok_s,
      rx_success => rx_done_s,
      idle_11    => idle11_s,
      tec => tec_out, rec => rec_out,
      err_active => em_active,
      err_passive => em_passive,
      bus_off => em_busoff
    );
  ack_drive_eff <= ack_drive_raw and (not tx_active);
  node_tx <= tx_bit_out and (not ack_drive_eff);
  can_tx <= '1'     when em_busoff = '1' else
            eg_bit  when eg_active = '1' else
            node_tx;
  tx_busy    <= tx_active;
  tx_done    <= ack_ok_s;
  tx_arblost <= arb_lost_s;
  tx_noack   <= ack_err_s;
  rx_valid   <= rx_done_s;
  rx_stuferr <= rxs_stuff_err;
  rx_crcerr  <= rx_crc_s;
  rx_formerr <= rx_form_s;
  err_active  <= em_active;
  err_passive <= em_passive;
  bus_off     <= em_busoff;
  err_frame   <= eg_active;
end rtl;
