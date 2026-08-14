library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity crc15 is
  generic (
    POLY : std_logic_vector(14 downto 0) := "100010110011001"
  );
  port (
    clk     : in  std_logic;
    reset_n : in  std_logic;
    crc_clr : in  std_logic;
    crc_en  : in  std_logic;
    crc_in  : in  std_logic;
    crc_out : out std_logic_vector(14 downto 0)
  );
end crc15;
architecture rtl of crc15 is
  signal crc_r : std_logic_vector(14 downto 0) := (others => '0');
begin
  process(clk, reset_n)
    variable shifted : std_logic_vector(14 downto 0);
    variable feedback : std_logic;
  begin
    if reset_n = '0' then
      crc_r <= (others => '0');
    elsif rising_edge(clk) then
      if crc_clr = '1' then
        crc_r <= (others => '0');
      elsif crc_en = '1' then
        feedback := crc_r(14) xor crc_in;
        shifted := crc_r(13 downto 0) & '0';
        if feedback = '1' then
          crc_r <= shifted xor POLY;
        else
          crc_r <= shifted;
        end if;
      end if;
    end if;
  end process;
  crc_out <= crc_r;
end rtl;
