------------------------------------------------------------------------------
--
--  FAMI - FPGA Arcade Machine Instauration
--  
--  Copyright (C) 2018 Denis Reischl
-- 
--  Project MiSTer and related files (C) 2017,2018 Sorgelig
--
--  Konami Framebuffer Arcade System Configuration
--  File <Framebuffer.vhd> (c) 2019 by Denis Reischl
--
--  EisernSchild/FAMI is licensed under the
--  GNU General Public License v3.0
--
------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.std_logic_unsigned.ALL;
library work;
use work.FAMI_package.all;

entity Framebuffer is
generic 
(	
	-- generic RAM integer constants
	constant nGenRamDataWidth      : integer := 8;     -- generic RAM 8 bit data width
	constant nGenRamAddrWidth		 : integer := 12;    -- generic RAM address width
	constant nGenRamADDrWidthVideo : integer := 15;    -- video RAM address width
	
	-- latch address constants
	constant nLatch             : std_logic_vector(15 downto 0) := X"FFFF" -- TODO !! LATCH ADRESSES
	
);
port
(
	i_Clk       : in std_logic; -- input clock  !! TODO !!
	i_Reset     : in std_logic; -- reset when 1
	
	o_RegData_cpu  : out std_logic_vector(111 downto 0);
	o_Debug_cpu : out std_logic_vector(15 downto 0);
	
	o_VGA_R4 : out std_logic_vector(3 downto 0); -- Red Color 4Bits
	o_VGA_G4 : out std_logic_vector(3 downto 0); -- Green Color 4Bits
	o_VGA_B4 : out std_logic_vector(3 downto 0)  -- Blue Color 4Bits
      
);
end Framebuffer;

architecture System of Framebuffer is

	-- Motorola 6809 CPU
	component mc6809 is
	port 
	(
		D        : in std_logic_vector(7 downto 0);   -- cpu data input 8 bit
		DOut     : out std_logic_vector(7 downto 0);  -- cpu data output 8 bit
		ADDR     : out std_logic_vector(15 downto 0); -- cpu address 16 bit
		RnW      : out std_logic;                     -- read enabled
		E        : out std_logic;                     -- output clock E
		Q        : out std_logic;                     -- output clock Q
		BS       : out	std_logic;                     -- bus status
		BA       : out std_logic;                     -- bus available
		nIRQ     : in std_logic;                      -- interrupt request
		nFIRQ    : in std_logic;                      -- fast interrupt request
		nNMI     : in std_logic;                      -- non-maskable interrupt
		EXTAL    : in std_logic;                      -- input oscillator
		XTAL     : in std_logic;                      -- input oscillator
		nHALT    : in std_logic; 							 -- not halt - causes the MPU to stop running
		nRESET   : in std_logic;                      -- not reset
		MRDY     : in std_logic;                      -- strech E and Q
		nDMABREQ : in std_logic;                      -- suspend execution
		RegData  : out std_logic_vector(111 downto 0) -- register data (debug)
	);
	end component mc6809;
	
	-- Main CPU
	signal cpu_clock_e    : std_logic;
	signal cpu_clock_q    : std_logic;
	signal cpu_addr       : std_logic_vector(15 downto 0);
	signal cpu_di         : std_logic_vector( 7 downto 0);
	signal cpu_do         : std_logic_vector( 7 downto 0);
	signal cpu_rw         : std_logic;
	signal cpu_irq        : std_logic;
	signal cpu_firq       : std_logic := '1';
	signal cpu_we, cpu_oe : std_logic;
	signal cpu_state      : std_logic_vector( 5 downto 0);
	signal cpu_bs, cpu_ba : std_logic;
	
	-- Main CPU Memory Signals
	signal cpu_wram_addr  : std_logic_vector(11 downto 0);
	signal cpu_wram_we    : std_logic;
	signal cpu_wram_do    : std_logic_vector( 7 downto 0);
	signal cpu_rom_addr   : std_logic_vector(11 downto 0);
	
	-- Video RAM Memory Signals
	signal video_wram_addr        : std_logic_vector(14 downto 0);
	signal video_wram_we          : std_logic;
	signal video_wram_do          : std_logic_vector( 7 downto 0);
	
--	-- CMOS signals (data-out and write-enabled)
--	signal cmos_do         : std_logic_vector( 7 downto 0);
--	signal cmos_we         : std_logic;
	
	-- Video control signals
	signal video_addr_output    : std_logic_vector(14 downto 0);
	signal video_pixel		    : std_logic_vector( 7 downto 0);
	
	-- PROM buses
	type   prom_buses_array is array (0 to 27) of std_logic_vector(7 downto 0);
	signal prom_buses : prom_buses_array;
	
	-- debug
	signal RegData_cpu  : std_logic_vector(111 downto 0);
	signal Debug_cpu : std_logic_vector(15 downto 0) := X"0000";
		
begin

	----------------------------------------------------------------------------------------------------------
	-- Clocks
	----------------------------------------------------------------------------------------------------------

lite_label : if LITE_BUILD generate
	-- debug program counter markers	
	debug_02 : process(cpu_clock_e)
	begin
		if rising_edge(cpu_clock_e) then
			case RegData_cpu(111 downto 96) is
				when X"fff1" => Debug_cpu(0) <= '1';
				when X"fff2" => Debug_cpu(1) <= '1';
				when X"fff3" => Debug_cpu(2) <= '1';
				when X"fff4" => Debug_cpu(3) <= '1';
				when X"fff5" => Debug_cpu(4) <= '1';
				when X"fff6" => Debug_cpu(5) <= '1';
				when others => Debug_cpu(15) <= '1';
			end case;
		end if;	
	end process debug_02;	
	o_RegData_cpu <= RegData_cpu;
	o_Debug_cpu <= Debug_cpu;
end generate;
	
	----------------------------------------------------------------------------------------------------------
	-- Components
	----------------------------------------------------------------------------------------------------------
	
	-- Main CPU : MC6809 ? MHz
	cpu_we <= not cpu_oe;
lite_label1 : if LITE_BUILD generate
	Data_Processor : mc6809
	port map
	(
		D        => cpu_di,      -- cpu data input 8 bit
		DOut     => cpu_do,      -- cpu data output 8 bit
		ADDR     => cpu_addr,    -- cpu address 16 bit
		RnW      => cpu_oe,      -- write enabled
		E        => cpu_clock_e, -- output clock E
		Q        => cpu_clock_q, -- output clock Q
		BS       => cpu_bs,      -- bus status
		BA       => cpu_ba,      -- bus available
		nIRQ     => not cpu_irq, -- interrupt request
		nFIRQ    => cpu_firq,    -- fast interrupt request
		nNMI     => '1',         -- non-maskable interrupt
		EXTAL    => i_Clk,       -- input oscillator
		XTAL     => '0',         -- input oscillator
		nHALT    => '1',         -- not halt - causes the MPU to stop running
		nRESET   => not i_Reset, -- not reset
		MRDY     => '1',         -- strech E and Q
		nDMABREQ => '1',         -- suspend execution
		RegData  => RegData_cpu  -- register data (debug)
	);
end generate;
	
	----------------------------------------------------------------------------------------------------------
	-- Memory Mapping
	----------------------------------------------------------------------------------------------------------
	
	-- $0000 - $7FFF : direct video RAM access - Page 0 $0000-$7FFF / Page 1 $8000-$FFFF
	Video_RAM : work.dpram generic map (nGenRamADDrWidthVideo, nGenRamDataWidth)
	port map
	(
		clock_a   => cpu_clock_e,
		wren_a    => video_wram_we,
		address_a => video_wram_addr,
		data_a    => cpu_do,
		q_a       => video_wram_do,

		clock_b   => i_Clk,
		address_b => video_addr_output,
		q_b       => video_pixel
	);
	
	-- $8000 - $8FFF : main cpu ram
	CPU_RAM : work.dpram generic map (nGenRamAddrWidth, nGenRamDataWidth)
	port map
	(
		clock_a   => cpu_clock_e,
		wren_a    => cpu_wram_we,
		address_a => cpu_wram_addr,
		data_a    => cpu_do,
		q_a       => cpu_wram_do,
		
		clock_b   => '0',
		address_b => (others => '0'),
		enable_b  => '0',
		q_b       => open
	);
	
	--	main cpu roms
	PROM_1H : entity work.PROM_H1 port map (CLK => cpu_clock_e, ADDR => cpu_rom_addr, DATA => prom_buses(0));   -- $0A000
	PROM_2H : entity work.PROM_H2 port map (CLK => cpu_clock_e, ADDR => cpu_rom_addr, DATA => prom_buses(1));   -- $0B000
	PROM_3H : entity work.PROM_H3 port map (CLK => cpu_clock_e, ADDR => cpu_rom_addr, DATA => prom_buses(2));   -- $0C000
	PROM_4H : entity work.PROM_H4 port map (CLK => cpu_clock_e, ADDR => cpu_rom_addr, DATA => prom_buses(3));   -- $0D000
	PROM_5H : entity work.PROM_H5 port map (CLK => cpu_clock_e, ADDR => cpu_rom_addr, DATA => prom_buses(4));   -- $0E000
	PROM_6H : entity work.PROM_H6 port map (CLK => cpu_clock_e, ADDR => cpu_rom_addr, DATA => prom_buses(5));   -- $0F000
	
	-- main cpu roms banked
	PROM_1I : entity work.PROM_J1 port map (CLK => cpu_clock_e, ADDR => cpu_rom_addr, DATA => prom_buses(6));   -- $10000
	PROM_2I : entity work.PROM_J2 port map (CLK => cpu_clock_e, ADDR => cpu_rom_addr, DATA => prom_buses(7));   -- $11000
	PROM_3I : entity work.PROM_J3 port map (CLK => cpu_clock_e, ADDR => cpu_rom_addr, DATA => prom_buses(8));   -- $12000
	PROM_4I : entity work.PROM_J4 port map (CLK => cpu_clock_e, ADDR => cpu_rom_addr, DATA => prom_buses(9));   -- $13000
	PROM_5I : entity work.PROM_J5 port map (CLK => cpu_clock_e, ADDR => cpu_rom_addr, DATA => prom_buses(10));  -- $14000
	PROM_6I : entity work.PROM_J6 port map (CLK => cpu_clock_e, ADDR => cpu_rom_addr, DATA => prom_buses(11));  -- $15000
	PROM_7I : entity work.PROM_J7	port map (CLK => cpu_clock_e, ADDR => cpu_rom_addr, DATA => prom_buses(12));  -- $16000
	PROM_8I : entity work.PROM_J8 port map (CLK => cpu_clock_e, ADDR => cpu_rom_addr, DATA => prom_buses(13));  -- $17000
	PROM_9I : entity work.PROM_J9 port map (CLK => cpu_clock_e, ADDR => cpu_rom_addr, DATA => prom_buses(14));  -- $18000
	
	--	
	-- PROM_7a : entity work.PROM_11_7A port map (CLK => spu_clock, ADDR => spu_rom_addr, DATA => prom_buses(27));
	-- PROM_8a : entity work.PROM_10_8A port map (CLK => spu_clock, ADDR => spu_rom_addr, DATA => prom_buses(27));
		
	----------------------------------------------------------------------------------------------------------
	-- Main Processor i/o control
	----------------------------------------------------------------------------------------------------------
	
	-- mux cpu in data between roms/io/wram
	cpu_di <=
		prom_buses(5) when cpu_addr(15 downto 8) >= X"F0" else
		prom_buses(4) when cpu_addr(15 downto 8) >= X"E0" else
		prom_buses(3) when cpu_addr(15 downto 8) >= X"D0" else
		prom_buses(2) when cpu_addr(15 downto 8) >= X"C0" else
		prom_buses(1) when cpu_addr(15 downto 8) >= X"B0" else
		prom_buses(0) when cpu_addr(15 downto 8) >= X"A0" else
		cpu_wram_do   when cpu_addr(15 downto 8) >= X"80" else video_wram_do;
		
	-- assign cpu in/out data addresses	
	cpu_rom_addr  <= cpu_addr(11 downto 0) when cpu_addr(15 downto 12) >= X"A" else X"000";
	cpu_wram_addr <= cpu_addr(11 downto 0) when ((cpu_addr(15 downto 12) >= X"8") and (cpu_addr(15 downto 12) < X"9")) else X"000";
	cpu_wram_we   <= cpu_we when ((cpu_addr(15 downto 12) >= X"8") and (cpu_addr(15 downto 12) < X"9")) else '0';
	video_wram_addr <= cpu_addr(14 downto 0) when (cpu_addr(15 downto 12) < X"8") else "000" & X"000";
	video_wram_we <= cpu_we when (cpu_addr(15 downto 12) < X"8") else '0';
	
	-- pixel output
	o_VGA_R4 <= video_pixel(7 downto 4);
	o_VGA_G4 <= video_pixel(7 downto 4);
	o_VGA_B4 <= video_pixel(3 downto 0);
	

end System;