library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity bit_timing is
  generic (
    SYNC_SEG   : integer := 1;
    PROP_SEG   : integer := 5;
    PHASE_SEG1 : integer := 6;
    PHASE_SEG2 : integer := 4;
    SJW        : integer := 4
  );
  port (
    clk        : in  std_logic;
    reset_n    : in  std_logic;
    can_rx     : in  std_logic;
    hard_sync  : in  std_logic;
    resync_en  : in  std_logic;
    tq_index   : out std_logic_vector(4 downto 0);
    sample_pt  : out std_logic;
    bit_start  : out std_logic;
    sampled_bit: out std_logic;
    seg_phase1 : out std_logic;
    seg_phase2 : out std_logic
  );
end bit_timing;
architecture rtl of bit_timing is
  constant END_SYNC   : integer := SYNC_SEG;
  constant END_PROP   : integer := SYNC_SEG + PROP_SEG;
  constant END_PHASE1 : integer := SYNC_SEG + PROP_SEG + PHASE_SEG1;
  constant BIT_TQ     : integer := SYNC_SEG + PROP_SEG
                                 + PHASE_SEG1 + PHASE_SEG2;
  signal tq_cnt : integer range 0 to 31 := 0;
  signal bit_len : integer range 1 to 31 := BIT_TQ;
  signal samp_at : integer range 0 to 31 := END_PHASE1 - 1;
  signal rx_prev : std_logic := '1';
  signal rx_edge : std_logic;
  signal did_resync : std_logic := '0';
  signal samp_r  : std_logic := '0';
  signal bitst_r : std_logic := '0';
  signal sbit_r  : std_logic := '1';
begin
  rx_edge <= '1' when (rx_prev = '1' and can_rx = '0') else '0';
  process(clk, reset_n)
    variable e    : integer range -31 to 31;
    variable corr : integer range 0 to 31;
  begin
    if reset_n = '0' then
      tq_cnt     <= 0;
      bit_len    <= BIT_TQ;
      samp_at    <= END_PHASE1 - 1;
      rx_prev    <= '1';
      did_resync <= '0';
      samp_r     <= '0';
      bitst_r    <= '0';
      sbit_r     <= '1';
    elsif rising_edge(clk) then
      rx_prev <= can_rx;
      samp_r  <= '0';
      bitst_r <= '0';
      if tq_cnt = samp_at and hard_sync = '0' then
        samp_r <= '1';
        sbit_r <= can_rx;
      end if;
      if hard_sync = '1' then
        tq_cnt     <= 0;
        bit_len    <= BIT_TQ;
        samp_at    <= END_PHASE1 - 1;
        did_resync <= '0';
        bitst_r    <= '1';
      elsif rx_edge = '1' and resync_en = '1' and did_resync = '0'
            and tq_cnt /= 0 then
        if tq_cnt < END_PHASE1 then
          e := tq_cnt;
        else
          e := tq_cnt - BIT_TQ;
        end if;
        if e > 0 then
          if e > SJW then corr := SJW; else corr := e; end if;
          bit_len    <= BIT_TQ + corr;
          samp_at    <= END_PHASE1 - 1 + corr;
          did_resync <= '1';
          tq_cnt     <= tq_cnt + 1;
        elsif e < 0 then
          if (-e) > SJW then corr := SJW; else corr := -e; end if;
          if (BIT_TQ - (tq_cnt + 1)) <= SJW then
            tq_cnt     <= 0;
            bit_len    <= BIT_TQ;
            samp_at    <= END_PHASE1 - 1;
            did_resync <= '0';
            bitst_r    <= '1';
          else
            bit_len    <= BIT_TQ - SJW;
            did_resync <= '1';
            tq_cnt     <= tq_cnt + 1;
          end if;
        else
          did_resync <= '1';
          tq_cnt     <= tq_cnt + 1;
        end if;
      elsif tq_cnt >= bit_len - 1 then
        tq_cnt     <= 0;
        bit_len    <= BIT_TQ;
        samp_at    <= END_PHASE1 - 1;
        did_resync <= '0';
        bitst_r    <= '1';
      else
        tq_cnt <= tq_cnt + 1;
      end if;
    end if;
  end process;
  tq_index    <= std_logic_vector(to_unsigned(tq_cnt, 5));
  sample_pt   <= samp_r;
  bit_start   <= bitst_r;
  sampled_bit <= sbit_r;
  seg_phase1 <= '1' when (tq_cnt >= END_PROP and tq_cnt <= samp_at) else '0';
  seg_phase2 <= '1' when (tq_cnt >  samp_at) else '0';
end rtl;
