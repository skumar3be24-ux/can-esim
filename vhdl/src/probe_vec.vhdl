library ieee;
use ieee.std_logic_1164.all;
entity probe_vec is
port(din : in std_logic_vector(3 downto 0);
     dout : out std_logic);
end probe_vec;
architecture bhv of probe_vec is
begin
	process(din)
	begin
		dout <= din(0) xor din(1) xor din(2) xor din(3);
	end process;
end bhv;
