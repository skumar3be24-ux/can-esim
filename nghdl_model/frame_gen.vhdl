library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity frame_gen is
  port (
    clk         : in  std_logic;
    reset_n     : in  std_logic;
    frame_start : in  std_logic;
    id_in       : in  std_logic_vector(10 downto 0);
    rtr_in      : in  std_logic;
    dlc_in      : in  std_logic_vector(3 downto 0);
    data_in     : in  std_logic_vector(63 downto 0);
    bit_en      : in  std_logic;
    bus_bit     : in  std_logic;
    sample_en   : in  std_logic;
    arb_abort   : in  std_logic;
    hold        : in  std_logic;
    tx_bit      : out std_logic;
    stuff_en    : out std_logic;
    frame_active: out std_logic;
    in_arb      : out std_logic;
    arb_lost    : out std_logic;
    ack_ok      : out std_logic;
    ack_err     : out std_logic;
    crc_clr     : out std_logic;
    crc_en      : out std_logic;
    crc_bit     : out std_logic;
    crc_val     : in  std_logic_vector(14 downto 0);
    field_id    : out std_logic_vector(3 downto 0)
  );
end frame_gen;
architecture rtl of frame_gen is
  type state_t is (
    ST_IDLE, ST_SOF, ST_ID, ST_RTR, ST_IDE, ST_R0, ST_DLC,
    ST_DATA, ST_CRC, ST_CRCDEL, ST_ACK, ST_ACKDEL, ST_EOF, ST_IFS
  );
  signal state : state_t := ST_IDLE;
  constant F_IDLE   : std_logic_vector(3 downto 0) := x"0";
  constant F_SOF    : std_logic_vector(3 downto 0) := x"1";
  constant F_ID     : std_logic_vector(3 downto 0) := x"2";
  constant F_RTR    : std_logic_vector(3 downto 0) := x"3";
  constant F_IDE    : std_logic_vector(3 downto 0) := x"4";
  constant F_R0     : std_logic_vector(3 downto 0) := x"5";
  constant F_DLC    : std_logic_vector(3 downto 0) := x"6";
  constant F_DATA   : std_logic_vector(3 downto 0) := x"7";
  constant F_CRC    : std_logic_vector(3 downto 0) := x"8";
  constant F_CRCDEL : std_logic_vector(3 downto 0) := x"9";
  constant F_ACK    : std_logic_vector(3 downto 0) := x"A";
  constant F_ACKDEL : std_logic_vector(3 downto 0) := x"B";
  constant F_EOF    : std_logic_vector(3 downto 0) := x"C";
  constant F_IFS    : std_logic_vector(3 downto 0) := x"D";
  signal id_r   : std_logic_vector(10 downto 0) := (others => '0');
  signal rtr_r  : std_logic := '0';
  signal dlc_r  : std_logic_vector(3 downto 0) := (others => '0');
  signal data_r : std_logic_vector(63 downto 0) := (others => '0');
  signal nbytes : integer range 0 to 8 := 0;
  signal bitcnt : integer range 0 to 63 := 0;
  signal tx_r    : std_logic := '1';
  signal stuff_r : std_logic := '0';
  signal act_r   : std_logic := '0';
  signal cclr_r  : std_logic := '0';
  signal cen_r   : std_logic := '0';
  signal cbit_r  : std_logic := '0';
  signal field_r : std_logic_vector(3 downto 0) := F_IDLE;
  signal arblost_r : std_logic := '0';
  signal ackok_r : std_logic := '0';
  signal ackerr_r: std_logic := '0';
  signal crc_lat : std_logic_vector(14 downto 0) := (others => '0');
begin
  process(clk, reset_n)
    variable dlc_int : integer range 0 to 15;
  begin
    if reset_n = '0' then
      state   <= ST_IDLE;
      bitcnt  <= 0;
      tx_r    <= '1';
      stuff_r <= '0';
      act_r   <= '0';
      cclr_r  <= '0';
      cen_r   <= '0';
      cbit_r  <= '0';
      field_r <= F_IDLE;
      nbytes  <= 0;
    elsif rising_edge(clk) then
      cclr_r   <= '0';
      cen_r    <= '0';
      ackok_r   <= '0';
      ackerr_r  <= '0';
      arblost_r <= '0';
      if state = ST_IDLE then
        tx_r    <= '1';
        stuff_r <= '0';
        act_r   <= '0';
        field_r <= F_IDLE;
        if frame_start = '1' then
          id_r   <= id_in;
          rtr_r  <= rtr_in;
          dlc_r  <= dlc_in;
          data_r <= data_in;
          dlc_int := to_integer(unsigned(dlc_in));
          if dlc_int > 8 then
            nbytes <= 8;
          else
            nbytes <= dlc_int;
          end if;
          cclr_r <= '1';
          state  <= ST_SOF;
          bitcnt <= 0;
          act_r  <= '1';
        end if;
      elsif arb_abort = '1' and act_r = '1' then
        arblost_r <= '1';
        tx_r      <= '1';
        act_r     <= '0';
        stuff_r   <= '0';
        state     <= ST_IDLE;
        field_r   <= F_IDLE;
        bitcnt    <= 0;
      elsif bit_en = '1' and hold = '0' then
        case state is
          when ST_SOF =>
            tx_r    <= '0';
            stuff_r <= '1';
            field_r <= F_SOF;
            cen_r   <= '1';
            cbit_r  <= '0';
            state   <= ST_ID;
            bitcnt  <= 0;
          when ST_ID =>
            tx_r    <= id_r(10 - bitcnt);
            stuff_r <= '1';
            field_r <= F_ID;
            cen_r   <= '1';
            cbit_r  <= id_r(10 - bitcnt);
            if bitcnt = 10 then
              state  <= ST_RTR;
              bitcnt <= 0;
            else
              bitcnt <= bitcnt + 1;
            end if;
          when ST_RTR =>
            tx_r    <= rtr_r;
            stuff_r <= '1';
            field_r <= F_RTR;
            cen_r   <= '1';
            cbit_r  <= rtr_r;
            state   <= ST_IDE;
          when ST_IDE =>
            tx_r    <= '0';
            stuff_r <= '1';
            field_r <= F_IDE;
            cen_r   <= '1';
            cbit_r  <= '0';
            state   <= ST_R0;
          when ST_R0 =>
            tx_r    <= '0';
            stuff_r <= '1';
            field_r <= F_R0;
            cen_r   <= '1';
            cbit_r  <= '0';
            state   <= ST_DLC;
            bitcnt  <= 0;
          when ST_DLC =>
            tx_r    <= dlc_r(3 - bitcnt);
            stuff_r <= '1';
            field_r <= F_DLC;
            cen_r   <= '1';
            cbit_r  <= dlc_r(3 - bitcnt);
            if bitcnt = 3 then
              bitcnt <= 0;
              if nbytes = 0 then
                state <= ST_CRC;
              else
                state <= ST_DATA;
              end if;
            else
              bitcnt <= bitcnt + 1;
            end if;
          when ST_DATA =>
            tx_r    <= data_r(63 - bitcnt);
            stuff_r <= '1';
            field_r <= F_DATA;
            cen_r   <= '1';
            cbit_r  <= data_r(63 - bitcnt);
            if bitcnt = (nbytes * 8) - 1 then
              state  <= ST_CRC;
              bitcnt <= 0;
            else
              bitcnt <= bitcnt + 1;
            end if;
          when ST_CRC =>
            if bitcnt = 0 then
              crc_lat <= crc_val;
              tx_r    <= crc_val(14);
            else
              tx_r    <= crc_lat(14 - bitcnt);
            end if;
            stuff_r <= '1';
            field_r <= F_CRC;
            if bitcnt = 14 then
              state  <= ST_CRCDEL;
              bitcnt <= 0;
            else
              bitcnt <= bitcnt + 1;
            end if;
          when ST_CRCDEL =>
            tx_r    <= '1';
            stuff_r <= '0';
            field_r <= F_CRCDEL;
            state   <= ST_ACK;
          when ST_ACK =>
            tx_r    <= '1';
            stuff_r <= '0';
            field_r <= F_ACK;
            state   <= ST_ACKDEL;
          when ST_ACKDEL =>
            if bus_bit = '0' then
              ackok_r  <= '1';
            else
              ackerr_r <= '1';
            end if;
            tx_r    <= '1';
            stuff_r <= '0';
            field_r <= F_ACKDEL;
            state   <= ST_EOF;
            bitcnt  <= 0;
          when ST_EOF =>
            tx_r    <= '1';
            stuff_r <= '0';
            field_r <= F_EOF;
            if bitcnt = 6 then
              state  <= ST_IFS;
              bitcnt <= 0;
              act_r  <= '0';
            else
              bitcnt <= bitcnt + 1;
            end if;
          when ST_IFS =>
            tx_r    <= '1';
            stuff_r <= '0';
            field_r <= F_IFS;
            if bitcnt = 2 then
              state  <= ST_IDLE;
              bitcnt <= 0;
            else
              bitcnt <= bitcnt + 1;
            end if;
          when others =>
            state <= ST_IDLE;
        end case;
      end if;
    end if;
  end process;
  tx_bit       <= tx_r;
  stuff_en     <= stuff_r;
  frame_active <= act_r;
  crc_clr      <= cclr_r;
  crc_en       <= cen_r;
  crc_bit      <= cbit_r;
  field_id     <= field_r;
  in_arb       <= '1' when (state = ST_SOF or state = ST_ID
                            or state = ST_RTR) else '0';
  arb_lost     <= arblost_r;
  ack_ok       <= ackok_r;
  ack_err      <= ackerr_r;
end rtl;
