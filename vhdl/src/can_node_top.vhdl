library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ============================================================
-- CAN node - NGHDL wrapper
-- Day 32, Phase 6 (pulled forward from Day 59)
--
-- can_node has a 64-bit tx_data and a 64-bit rx_data, which would
-- produce an unusable SPICE symbol - NGHDL creates one pin per bit
-- and one socket round trip per event. This wrapper exposes only
-- what has to cross the analog boundary.
--
-- The frame contents are selected by id_sel from a small table of
-- presets, so the SPICE side only needs to assert tx_req and pick
-- a node identity.
--
--   id_sel  identifier  payload
--   "00"    0x0A5       0xA5
--   "01"    0x123       0x3C
--   "10"    0x2AA       0x77
--   "11"    0x555       0xE1
--
-- FORMATTING WARNING
--   NGHDL parses this entity line by line and is sensitive to
--   layout. The style below matches customblock.vhdl, which is the
--   only style the parser was verified against on Day 11. Do not
--   reformat the port list.
--
--   No generics: NGHDL's model_generation.py does not handle them.
--   The bit timing constants are fixed to the frozen values.
-- ============================================================

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

  -- ---- preset frame contents, chosen by id_sel ----
  -- Kept as a concurrent selection rather than a process so there
  -- is no extra clock of latency before tx_req takes effect.
  sel_id <= "00010100101" when id_sel = "00" else   -- 0x0A5
            "00100100011" when id_sel = "01" else   -- 0x123
            "01010101010" when id_sel = "10" else   -- 0x2AA
            "10101010101";                          -- 0x555

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
