-- ============================================================
-- CAN node - complete transmit + receive controller
-- Day 31, Phase 4
--
-- One self-contained CAN node. This is the unit that becomes the
-- NGHDL model for the mixed-signal simulation, so the port list is
-- kept flat and simple - NGHDL parses it line by line and is
-- sensitive to formatting.
--
--   host --tx_req--> [ can_tx_path ] --+--> can_tx (to the bus)
--                                      |
--                    [ ack drive ] ----+
--
--   can_rx (from bus) --> [ bit_stuff rx ] --> [ frame_rx ] --> host
--
-- STRUCTURE
--   One bit_timing per node, inside can_tx_path, drives BOTH
--   directions. A node has a single view of where bit boundaries
--   are; giving transmit and receive separate timing would be
--   wrong.
--
-- A TRANSMITTER MUST NOT ACK ITS OWN FRAME
--   In CAN the ACK comes from OTHER nodes. A transmitter that
--   acknowledged itself would always see a dominant ACK slot and
--   could never detect that nobody heard it - the Day 29 ack_err
--   path would be dead. ack_drive is therefore suppressed while
--   this node is transmitting.
--
-- SELF-RECEPTION
--   The node's receive chain sees its own transmitted bits,
--   because the bus is shared and can_rx carries whatever is on
--   the wire. That is deliberate: it is how the transmitter
--   monitors the bus for arbitration (Day 30) and for the ACK
--   slot (Day 29).
--
-- WHAT IS NOT HERE YET
--   No error frames, no TEC/REC counters, no bus-off state, no
--   automatic retransmission after losing arbitration. Phase 5.
-- ============================================================

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
    clk       : in  std_logic;   -- 2.000 MHz, one time quantum
    reset_n   : in  std_logic;

    -- ---------------- bus ----------------
    can_rx    : in  std_logic;   -- bus level in
    can_tx    : out std_logic;   -- this node's contribution out

    -- ---------------- transmit request ----------------
    tx_req    : in  std_logic;   -- one-cycle pulse to send a frame
    tx_id     : in  std_logic_vector(10 downto 0);
    tx_rtr    : in  std_logic;
    tx_dlc    : in  std_logic_vector(3 downto 0);
    tx_data   : in  std_logic_vector(63 downto 0);

    -- ---------------- transmit status ----------------
    tx_busy   : out std_logic;   -- frame in progress
    tx_done   : out std_logic;   -- pulse: frame sent and acknowledged
    tx_arblost: out std_logic;   -- pulse: lost arbitration
    tx_noack  : out std_logic;   -- pulse: nobody acknowledged

    -- ---------------- receive ----------------
    rx_valid  : out std_logic;   -- pulse: a good frame was received
    rx_id     : out std_logic_vector(10 downto 0);
    rx_rtr    : out std_logic;
    rx_dlc    : out std_logic_vector(3 downto 0);
    rx_data   : out std_logic_vector(63 downto 0);
    rx_crcerr : out std_logic;   -- pulse
    rx_formerr: out std_logic;   -- pulse
    rx_stuferr: out std_logic;   -- pulse

    -- ---------------- fault confinement ----------------
    tec_out    : out std_logic_vector(8 downto 0);
    rec_out    : out std_logic_vector(8 downto 0);
    err_active : out std_logic;  -- error-active state
    err_passive: out std_logic;  -- error-passive state
    bus_off    : out std_logic;  -- disconnected
    err_frame  : out std_logic   -- high while sending an error frame
  );
end can_node;

architecture rtl of can_node is

  -- transmit path
  signal tx_bit_out : std_logic;
  signal tx_active  : std_logic;
  signal tx_field   : std_logic_vector(3 downto 0);
  signal bit_slot   : std_logic;
  signal sample_now : std_logic;
  signal stuff_now  : std_logic;
  signal arb_lost_s : std_logic;
  signal ack_ok_s   : std_logic;
  signal ack_err_s  : std_logic;

  -- receive chain
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

  -- error paths
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

  -- bus level latched at the sample point. error_gen advances at
  -- the START of a bit slot so its output is stable by the sample
  -- point, but it must READ the bus as sampled - two different
  -- instants, so the level has to be held.
  signal bus_sampled : std_logic := '1';

  -- 11 consecutive recessive bits, for bus-off recovery
  signal rec_run  : integer range 0 to 15 := 0;
  signal idle11_s : std_logic := '0';

  signal node_tx    : std_logic;
  signal bit_err_s  : std_logic;
  signal in_ack_s   : std_logic;
  signal tx_err_any : std_logic;
  signal tx_req_gated : std_logic;
  signal busoff_d1    : std_logic := '0';
  signal busoff_edge  : std_logic;

begin

  -- ============ transmit path ============
  u_tx : entity work.can_tx_path
    generic map (
      SYNC_SEG => SYNC_SEG, PROP_SEG => PROP_SEG,
      PHASE_SEG1 => PHASE_SEG1, PHASE_SEG2 => PHASE_SEG2,
      SJW => SJW
    )
    port map (
      clk => clk, reset_n => reset_n,
      frame_start => tx_req_gated,
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
      abort_in    => busoff_edge,
      arb_lost => arb_lost_s,
      ack_ok => ack_ok_s,
      ack_err => ack_err_s
    );

  -- ============ receive chain ============
  -- one destuffed bit per sample point
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

  -- ============ bus-off suppression ============
  -- A bus-off node must not START a frame...
  tx_req_gated <= tx_req and (not em_busoff);

  -- ...and must ABANDON one already in progress. A one-cycle pulse
  -- on entering bus-off drops the current frame; holding it would
  -- keep re-triggering the abort branch forever.
  process(clk, reset_n)
  begin
    if reset_n = '0' then
      busoff_d1 <= '0';
    elsif rising_edge(clk) then
      busoff_d1 <= em_busoff;
    end if;
  end process;
  busoff_edge <= em_busoff and (not busoff_d1);

  -- the ACK slot, where a dominant readback is expected rather
  -- than an error
  -- Suppress monitoring across the CRC delimiter, ACK slot and ACK
  -- delimiter. tx_field is frame_gen CURRENT field, but tx_r is
  -- REGISTERED, so the bit for field N reaches the bus while the
  -- FSM already reads N+1. Excluding only 0xA masked the wrong slot
  -- and every acknowledged frame raised a spurious bit error, which
  -- triggered an error frame and corrupted normal traffic.
  -- Covering 0x9..0xB spans the lag in either direction.
  in_ack_s <= '1' when (tx_field = x"9" or tx_field = x"A"
                        or tx_field = x"B") else '0';

  -- ============ error event routing ============
  -- Any receive-side error starts an error frame and bumps REC.
  -- While WE are transmitting an error frame the bus is
  -- deliberately full of stuff violations - our own. Counting
  -- those would cascade: Day 35 measured 17 errors from a single
  -- corrupted frame because of exactly this.
  any_rx_err <= (rx_crc_s or rx_form_s or rxs_stuff_err)
                and (not eg_active);

  -- A bit error is a transmit-side fault and also starts an error
  -- frame.
  tx_err_any <= (bit_err_s or ack_err_s) and (not eg_active);

  err_req_s  <= any_rx_err or tx_err_any;

  -- ============ bus level sampling and idle detection ============
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
        -- count consecutive recessive bits for bus-off recovery
        if can_rx = '1' then
          if rec_run >= 10 then
            idle11_s <= '1';     -- 11 recessive bits seen
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

  -- ============ error frame generator ============
  u_errgen : entity work.error_gen
    port map (
      clk => clk, reset_n => reset_n,
      bit_en     => bit_slot,       -- advance at the slot start
      bus_bit    => bus_sampled,    -- read the level as sampled
      err_req    => err_req_s,
      is_passive => em_passive,
      err_active => eg_active,
      err_bit    => eg_bit,
      err_done   => eg_done,
      stuck_bus  => eg_stuck
    );

  -- ============ fault confinement counters ============
  u_errmgmt : entity work.error_mgmt
    port map (
      clk => clk, reset_n => reset_n,
      -- a transmitter that got no ACK caused the problem: +8
      tx_error   => tx_err_any,
      -- receive-side errors: +1
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

  -- ============ ACK gating ============
  -- Do NOT acknowledge our own frame. A transmitter that ACKed
  -- itself would always see a dominant ACK slot and could never
  -- detect that nobody heard it.
  ack_drive_eff <= ack_drive_raw and (not tx_active);

  -- ============ bus contribution ============
  -- Priority:
  --   BUS OFF      -> drive nothing, always recessive. The node is
  --                   disconnected and must not disturb the bus.
  --   ERROR FRAME  -> error_gen owns the output. Its flag has to
  --                   reach the bus even mid-frame; that is the
  --                   whole mechanism for destroying a bad frame.
  --   NORMAL       -> transmit bit, wired-AND with the ACK drive.
  node_tx <= tx_bit_out and (not ack_drive_eff);

  can_tx <= '1'     when em_busoff = '1' else
            eg_bit  when eg_active = '1' else
            node_tx;

  -- ============ status ============
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
