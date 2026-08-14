library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity can_tx_path is
  generic (
    SYNC_SEG   : integer := 1;
    PROP_SEG   : integer := 5;
    PHASE_SEG1 : integer := 6;
    PHASE_SEG2 : integer := 4;
    SJW        : integer := 4
  );
  port (
    clk         : in  std_logic;
    reset_n     : in  std_logic;
    frame_start : in  std_logic;
    id_in       : in  std_logic_vector(10 downto 0);
    rtr_in      : in  std_logic;
    dlc_in      : in  std_logic_vector(3 downto 0);
    data_in     : in  std_logic_vector(63 downto 0);
    can_rx      : in  std_logic;
    can_tx      : out std_logic;
    frame_active: out std_logic;
    field_id    : out std_logic_vector(3 downto 0);
    bit_slot    : out std_logic;
    sample_now  : out std_logic;
    stuff_now   : out std_logic;
    bit_err     : out std_logic;
    in_ack_slot : in  std_logic;
    abort_in    : in  std_logic;
    arb_lost    : out std_logic;
    ack_ok      : out std_logic;
    ack_err     : out std_logic
  );
end can_tx_path;
architecture rtl of can_tx_path is
  signal tq_index    : std_logic_vector(4 downto 0);
  signal sample_pt   : std_logic;
  signal bit_start   : std_logic;
  signal sampled_bit : std_logic;
  signal seg_phase1  : std_logic;
  signal seg_phase2  : std_logic;
  signal fg_tx_bit   : std_logic;
  signal fg_stuff_en : std_logic;
  signal fg_active   : std_logic;
  signal fg_arblost  : std_logic;
  signal fg_in_arb   : std_logic;
  signal biterr_s    : std_logic;
  signal arb_abort_s : std_logic;
  signal driven_bit  : std_logic;
  signal fg_ack_ok   : std_logic;
  signal fg_ack_err  : std_logic;
  signal fg_field    : std_logic_vector(3 downto 0);
  signal crc_clr : std_logic;
  signal crc_en  : std_logic;
  signal crc_bit : std_logic;
  signal crc_val : std_logic_vector(14 downto 0);
  signal tx_slot_en : std_logic;
  signal st_bit_out : std_logic;
  signal st_stall   : std_logic;
  signal st_stall_c : std_logic;
  signal st_rx_bit_out : std_logic;
  signal st_rx_valid   : std_logic;
  signal st_rx_discard : std_logic;
  signal st_stuff_err  : std_logic;
begin
  tx_slot_en <= bit_start and fg_active;
  driven_bit  <= st_bit_out when fg_active = '1' else '1';
  biterr_s <= '1' when (sample_pt = '1' and fg_active = '1'
                        and fg_in_arb = '0'
                        and in_ack_slot = '0'
                        and driven_bit /= can_rx)
              else '0';
  arb_abort_s <= '1' when (abort_in = '1')
                      or (sample_pt = '1' and fg_active = '1'
                          and fg_in_arb = '1'
                          and driven_bit = '1' and can_rx = '0')
                 else '0';
  u_timing : entity work.bit_timing
    generic map (
      SYNC_SEG => SYNC_SEG, PROP_SEG => PROP_SEG,
      PHASE_SEG1 => PHASE_SEG1, PHASE_SEG2 => PHASE_SEG2,
      SJW => SJW
    )
    port map (
      clk => clk, reset_n => reset_n,
      can_rx => can_rx,
      hard_sync => '0',
      resync_en => '1',
      tq_index => tq_index,
      sample_pt => sample_pt,
      bit_start => bit_start,
      sampled_bit => sampled_bit,
      seg_phase1 => seg_phase1,
      seg_phase2 => seg_phase2
    );
  u_frame : entity work.frame_gen
    port map (
      clk => clk, reset_n => reset_n,
      frame_start => frame_start,
      id_in => id_in, rtr_in => rtr_in,
      dlc_in => dlc_in, data_in => data_in,
      bit_en  => bit_start,
      bus_bit   => can_rx,
      sample_en => sample_pt,
      arb_abort => arb_abort_s,
      hold    => st_stall_c,
      tx_bit => fg_tx_bit,
      stuff_en => fg_stuff_en,
      frame_active => fg_active,
      in_arb   => fg_in_arb,
      arb_lost => fg_arblost,
      ack_ok  => fg_ack_ok,
      ack_err => fg_ack_err,
      crc_clr => crc_clr, crc_en => crc_en,
      crc_bit => crc_bit, crc_val => crc_val,
      field_id => fg_field
    );
  u_crc : entity work.crc15
    port map (
      clk => clk, reset_n => reset_n,
      crc_clr => crc_clr, crc_en => crc_en,
      crc_in => crc_bit, crc_out => crc_val
    );
  u_stuff : entity work.bit_stuff
    generic map (STUFF_LEN => 5)
    port map (
      clk => clk, reset_n => reset_n,
      tx_en       => tx_slot_en,
      tx_bit_in   => fg_tx_bit,
      tx_stuff_en => fg_stuff_en,
      tx_bit_out  => st_bit_out,
      tx_stall    => st_stall,
      tx_stall_c  => st_stall_c,
      rx_en       => '0',
      rx_bit_in   => '1',
      rx_stuff_en => '0',
      rx_bit_out  => st_rx_bit_out,
      rx_valid    => st_rx_valid,
      rx_discard  => st_rx_discard,
      stuff_err   => st_stuff_err
    );
  can_tx <= st_bit_out when fg_active = '1' else '1';
  frame_active <= fg_active;
  field_id     <= fg_field;
  bit_slot     <= bit_start;
  sample_now   <= sample_pt;
  stuff_now    <= st_stall;
  bit_err      <= biterr_s;
  arb_lost     <= fg_arblost;
  ack_ok       <= fg_ack_ok;
  ack_err      <= fg_ack_err;
end rtl;
