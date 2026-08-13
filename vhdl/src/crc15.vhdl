-- ============================================================
-- CAN CRC-15
-- Day 25, Phase 3
--
-- Generator polynomial (ISO 11898-1):
--   x^15 + x^14 + x^10 + x^8 + x^7 + x^4 + x^3 + 1  =  0x4599
--
-- PER-BIT ALGORITHM
--   msb  = crc(14)
--   crc  = crc(13 downto 0) & '0'          -- shift left
--   if (msb xor data_bit) = '1' then
--     crc = crc xor 0x4599
--   end if
--
-- The register initialises to ZERO. An all-zero input must
-- therefore produce an all-zero CRC - nothing ever sets a bit.
-- That is the cheapest possible sanity check and it catches a
-- register that fails to reset.
--
-- COVERAGE - what the CRC is computed over
--   SOF, identifier, RTR, IDE, r0, DLC, and the data field.
--   It STOPS before the CRC sequence itself.
--
-- CRITICAL: the CRC operates on DESTUFFED bits. Stuff bits are a
-- physical-layer artefact and are never included. Computing the
-- CRC over the stuffed bus stream produces a value the receiver
-- can never match - a real and common implementation error.
--
-- USAGE
--   Assert crc_clr for one cycle to start a new frame, then pulse
--   crc_en once per destuffed bit with that bit on crc_in.
--   crc_out is valid combinationally after each enabled bit.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity crc15 is
  generic (
    POLY : std_logic_vector(14 downto 0) := "100010110011001"  -- 0x4599
  );
  port (
    clk     : in  std_logic;
    reset_n : in  std_logic;

    crc_clr : in  std_logic;   -- one cycle: reset the register to 0
    crc_en  : in  std_logic;   -- one pulse per destuffed bit
    crc_in  : in  std_logic;   -- the destuffed bit

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
        -- feedback is the incoming bit XORed with the register MSB
        feedback := crc_r(14) xor crc_in;

        -- shift left, LSB filled with 0
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
