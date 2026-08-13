-- ============================================================
-- CAN transmit datapath
-- Day 27, Phase 3 - integration
--
-- Wires the three verified modules into a complete transmit path:
--
--   frame_gen --tx_bit--> bit_stuff --tx_bit_out--> can_tx
--       ^                     |
--       +------ hold ---------+   (tx_stall: stuff bit sent,
--       |                          payload NOT consumed)
--   stuff_en ---------------> tx_stuff_en
--
--   bit_timing --bit_start--> both, one pulse per bit slot
--
-- BACK-PRESSURE - the point of this integration
--   When bit_stuff inserts a stuff bit it asserts tx_stall. The
--   payload bit frame_gen offered that slot was NOT taken, so
--   frame_gen must hold and re-offer it. This is the first
--   back-pressure relationship in the design and the most likely
--   place for an integration bug: get it wrong and exactly one
--   payload bit is dropped per stuff bit, which corrupts the
--   frame in a way that only shows up on stuffing-heavy payloads.
--
-- TIMING
--   bit_timing runs at 2.000 MHz, 16 tq per bit -> 8.000 us per
--   bit slot -> 125 kbit/s, per the frozen spec.
--   A DLC=0 frame is 47 payload bits plus stuff bits, so roughly
--   50 slots, about 400 us.
--
-- BUS IDLE
--   can_tx is recessive whenever no frame is active. The stuffer
--   output is only gated onto the bus during a frame.
--
-- WHAT THIS DOES NOT DO YET
--   No arbitration, no ACK checking, no error handling, no
--   receive path. Those are Phase 4 and Phase 5. This module
--   only proves the three transmit-side blocks work together and
--   produce a correctly stuffed stream at the right bit rate.
-- ============================================================

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
    clk         : in  std_logic;   -- 2.000 MHz (one tq)
    reset_n     : in  std_logic;

    -- ---- frame request ----
    frame_start : in  std_logic;
    id_in       : in  std_logic_vector(10 downto 0);
    rtr_in      : in  std_logic;
    dlc_in      : in  std_logic_vector(3 downto 0);
    data_in     : in  std_logic_vector(63 downto 0);

    -- ---- bus ----
    can_rx      : in  std_logic;   -- for bit_timing resync
    can_tx      : out std_logic;   -- stuffed stream, recessive when idle

    -- ---- status ----
    frame_active: out std_logic;
    field_id    : out std_logic_vector(3 downto 0);
    bit_slot    : out std_logic;   -- one pulse per bit slot
    stuff_now   : out std_logic    -- high when a stuff bit is on the bus
  );
end can_tx_path;

architecture rtl of can_tx_path is

  -- bit timing
  signal tq_index    : std_logic_vector(4 downto 0);
  signal sample_pt   : std_logic;
  signal bit_start   : std_logic;
  signal sampled_bit : std_logic;
  signal seg_phase1  : std_logic;
  signal seg_phase2  : std_logic;

  -- frame generator
  signal fg_tx_bit   : std_logic;
  signal fg_stuff_en : std_logic;
  signal fg_active   : std_logic;
  signal fg_field    : std_logic_vector(3 downto 0);

  -- CRC
  signal crc_clr : std_logic;
  signal crc_en  : std_logic;
  signal crc_bit : std_logic;
  signal crc_val : std_logic_vector(14 downto 0);

  -- gated bit-slot enable: bit_start free-runs whether or not a
  -- frame is active, so the stuffer must only be enabled during a
  -- frame. Ungated, it counts identical idle-recessive bits forever
  -- and overflows its run counter.
  signal tx_slot_en : std_logic;

  -- stuffer
  signal st_bit_out : std_logic;
  signal st_stall   : std_logic;
  signal st_stall_c : std_logic;

  -- unused receive side of bit_stuff
  signal st_rx_bit_out : std_logic;
  signal st_rx_valid   : std_logic;
  signal st_rx_discard : std_logic;
  signal st_stuff_err  : std_logic;

begin

  tx_slot_en <= bit_start and fg_active;

  -- ============ bit timing: one pulse per bit slot ============
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

  -- ============ frame generator ============
  u_frame : entity work.frame_gen
    port map (
      clk => clk, reset_n => reset_n,
      frame_start => frame_start,
      id_in => id_in, rtr_in => rtr_in,
      dlc_in => dlc_in, data_in => data_in,
      bit_en => bit_start,
      hold   => st_stall_c,        -- <<< back-pressure (combinational)
      tx_bit => fg_tx_bit,
      stuff_en => fg_stuff_en,
      frame_active => fg_active,
      crc_clr => crc_clr, crc_en => crc_en,
      crc_bit => crc_bit, crc_val => crc_val,
      field_id => fg_field
    );

  -- ============ CRC-15 ============
  u_crc : entity work.crc15
    port map (
      clk => clk, reset_n => reset_n,
      crc_clr => crc_clr, crc_en => crc_en,
      crc_in => crc_bit, crc_out => crc_val
    );

  -- ============ bit stuffer ============
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
      -- receive side unused in this module
      rx_en       => '0',
      rx_bit_in   => '1',
      rx_stuff_en => '0',
      rx_bit_out  => st_rx_bit_out,
      rx_valid    => st_rx_valid,
      rx_discard  => st_rx_discard,
      stuff_err   => st_stuff_err
    );

  -- ============ bus output ============
  -- recessive whenever no frame is in progress
  can_tx <= st_bit_out when fg_active = '1' else '1';

  frame_active <= fg_active;
  field_id     <= fg_field;
  bit_slot     <= bit_start;
  stuff_now    <= st_stall;

end rtl;
