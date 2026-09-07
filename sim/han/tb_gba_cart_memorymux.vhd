library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.pProc_bus_gba.all;

entity tb_gba_cart_memorymux is end entity;
architecture test of tb_gba_cart_memorymux is
   signal clk : std_logic := '0';
   signal reset : std_logic := '0';
   signal ss_bus, gb_bus : proc_bus_gb_type := ((others => 'Z'), (others => 'Z'), (others => 'Z'), 'Z', '0', 'Z', "ZZ", "ZZZZ", '0');
   signal cart_save_mode : std_logic := '1';
   signal cart_save_req, cart_save_rnw, cart_save_done : std_logic := '0';
   signal cart_save_addr : std_logic_vector(16 downto 0);
   signal cart_save_din : std_logic_vector(7 downto 0);
   signal cart_save_dout : std_logic_vector(7 downto 0) := x"A5";
   signal cart_eeprom_req, cart_eeprom_rnw, cart_eeprom_din, cart_eeprom_dma, cart_eeprom_last, cart_eeprom_done : std_logic := '0';
   signal cart_eeprom_dout : std_logic := '1';
   signal cart_eeprom_count : std_logic_vector(16 downto 0);
   signal mem_bus_dma3, dma3_active : std_logic := '0';
   signal dma_eepromcount : unsigned(16 downto 0) := (others => '0');
   signal mem_bus_adr, mem_bus_dout, mem_bus_din : std_logic_vector(31 downto 0) := (others => '0');
   signal mem_bus_acc : std_logic_vector(1 downto 0) := ACCESS_8BIT;
   signal mem_bus_rnw, mem_bus_ena, mem_bus_done : std_logic := '0';
   signal bus_out_ena, bus_out_done, bus_out_rnw : std_logic := '0';
   signal bus_out_adr : std_logic_vector(25 downto 0);
   signal bus_out_din : std_logic_vector(31 downto 0);
   signal save_eeprom, save_sram, save_flash : std_logic;
   signal save_requests, eeprom_requests, sd_requests : natural := 0;
begin
   clk <= not clk after 5 ns;
   dut : entity work.gba_memorymux
      generic map (is_simu => '1', Softmap_GBA_Gamerom_ADDR => 0,
         Softmap_GBA_WRam_ADDR => 8388608, Softmap_GBA_FLASH_ADDR => 16777216,
         Softmap_GBA_EEPROM_ADDR => 16908288)
      port map (
      clk100 => clk,
      gb_on => '1',
      reset => reset,
      savestate_bus => ss_bus,
      sdram_read_ena => open,
      sdram_read_done => '0',
      sdram_read_addr => open,
      sdram_read_data => (others => '0'),
      sdram_second_dword => (others => '0'),
      bus_out_Din => bus_out_din,
      bus_out_Dout => x"000000A5",
      bus_out_Adr => bus_out_adr,
      bus_out_rnw => bus_out_rnw,
      bus_out_ena => bus_out_ena,
      bus_out_done => bus_out_done,
      gb_bus_out => gb_bus,
      mem_bus_Adr => mem_bus_adr,
      mem_bus_rnw => mem_bus_rnw,
      mem_bus_ena => mem_bus_ena,
      mem_bus_acc => mem_bus_acc,
      mem_bus_dout => mem_bus_dout,
      mem_bus_din => mem_bus_din,
      mem_bus_done => mem_bus_done,
      mem_bus_unread => open,
      bios_wraddr => (others => '0'),
      bios_wrdata => (others => '0'),
      bios_wr => '0',
      bus_lowbits => (others => '0'),
      dma_soon => '0',
      settle => open,
      save_eeprom => save_eeprom,
      save_sram => save_sram,
      save_flash => save_flash,
      new_cycles => (others => '0'),
      new_cycles_valid => '0',
      PC_in_BIOS => '0',
      lastread => (others => '0'),
      lastread_dma => (others => '0'),
      last_access_dma => '0',
      cart_save_mode => cart_save_mode,
      cart_save_req => cart_save_req,
      cart_save_addr => cart_save_addr,
      cart_save_rnw => cart_save_rnw,
      cart_save_din => cart_save_din,
      cart_save_dout => cart_save_dout,
      cart_save_done => cart_save_done,
      cart_eeprom_req => cart_eeprom_req,
      cart_eeprom_rnw => cart_eeprom_rnw,
      cart_eeprom_din => cart_eeprom_din,
      cart_eeprom_dma => cart_eeprom_dma,
      cart_eeprom_last => cart_eeprom_last,
      cart_eeprom_count => cart_eeprom_count,
      cart_eeprom_dout => cart_eeprom_dout,
      cart_eeprom_done => cart_eeprom_done,
      mem_bus_dma3 => mem_bus_dma3,
      dma3_active => dma3_active,
      dma_eepromcount => dma_eepromcount,
      flash_1m => '0',
      MaxPakAddr => (others => '0'),
      SramFlashEnable => '1',
      memory_remap => '0',
      bitmapdrawmode => '0',
      VRAM_Lo_addr => open,
      VRAM_Lo_datain => open,
      VRAM_Lo_dataout => (others => '0'),
      VRAM_Lo_we => open,
      VRAM_Lo_be => open,
      VRAM_Hi_addr => open,
      VRAM_Hi_datain => open,
      VRAM_Hi_dataout => (others => '0'),
      VRAM_Hi_we => open,
      VRAM_Hi_be => open,
      vram_blocked => '0',
      vram_cycle => open,
      OAMRAM_PROC_addr => open,
      OAMRAM_PROC_datain => open,
      OAMRAM_PROC_dataout => (others => '0'),
      OAMRAM_PROC_we => open,
      PALETTE_BG_addr => open,
      PALETTE_BG_datain => open,
      PALETTE_BG_dataout => (others => '0'),
      PALETTE_BG_we => open,
      PALETTE_OAM_addr => open,
      PALETTE_OAM_datain => open,
      PALETTE_OAM_dataout => (others => '0'),
      PALETTE_OAM_we => open,
      specialmodule => '0',
      GPIO_readEna => open,
      GPIO_done => '0',
      GPIO_Din => (others => '0'),
      GPIO_Dout => open,
      GPIO_writeEna => open,
      GPIO_addr => open,
      tilt => '0',
      AnalogTiltX => (others => '0'),
      AnalogTiltY => (others => '0'),
      debug_mem => open
      );
   responder : process(clk)
   begin
      if rising_edge(clk) then
         cart_save_done <= cart_save_req;
         cart_eeprom_done <= cart_eeprom_req;
         bus_out_done <= bus_out_ena;
         if cart_save_req = '1' then save_requests <= save_requests + 1; end if;
         if cart_eeprom_req = '1' then eeprom_requests <= eeprom_requests + 1; end if;
         if bus_out_ena = '1' then sd_requests <= sd_requests + 1; end if;
         if cart_save_mode = '1' then
            assert bus_out_ena = '0' report "Cartridge save escaped to SD backing memory" severity failure;
            assert save_eeprom = '0' and save_sram = '0' and save_flash = '0'
               report "Cartridge transaction dirtied SD save" severity failure;
         else
            assert cart_save_req = '0' and cart_eeprom_req = '0'
               report "SD save touched physical cartridge" severity failure;
         end if;
      end if;
   end process;
   stimulus : process
      procedure access_bus(a : std_logic_vector(31 downto 0); rnw : std_logic;
         d : std_logic_vector(31 downto 0); acc : std_logic_vector(1 downto 0) := ACCESS_8BIT) is
         variable completed : boolean := false;
      begin
         wait until falling_edge(clk);
         mem_bus_adr <= a; mem_bus_rnw <= rnw; mem_bus_dout <= d; mem_bus_acc <= acc; mem_bus_ena <= '1';
         wait until falling_edge(clk); mem_bus_ena <= '0';
         for i in 0 to 100 loop
            wait until falling_edge(clk);
            if mem_bus_done = '1' then completed := true; exit; end if;
         end loop;
         assert completed report "Memory request did not complete" severity failure;
      end procedure;
      type count_list is array(natural range <>) of natural;
      constant command_counts : count_list := (9, 17, 73, 81);
      variable before_count : natural;
   begin
      wait for 100 ns;
      -- Raw Flash unlock, bank and ID command bytes must reach the chip,
      -- with no emulated ID substitution or bank-address translation.
      access_bus(x"0E005555", '0', x"000000AA");
      assert save_requests = 1 and cart_save_addr = std_logic_vector(to_unsigned(16#5555#, 17)) and cart_save_din = x"AA" severity failure;
      access_bus(x"0E002AAA", '0', x"00000055");
      access_bus(x"0E005555", '0', x"000000B0");
      access_bus(x"0E000000", '0', x"00000001");
      access_bus(x"0E000012", '1', x"00000000");
      assert mem_bus_din = x"000000A5" and cart_save_addr = std_logic_vector(to_unsigned(16#12#, 17)) severity failure;
      access_bus(x"0F000014", '1', x"00000000", ACCESS_32BIT);
      assert mem_bus_din = x"A5A5A5A5" severity failure;
      access_bus(x"0E000015", '1', x"00000000", ACCESS_16BIT);
      assert mem_bus_din = x"A50000A5" severity failure;
      -- A full DMA3 command ends exactly at its programmed count. Address
      -- bit1 must not change serial write D0 or move the returned bit.
      dma3_active <= '1'; mem_bus_dma3 <= '1';
      for count_id in command_counts'range loop
      dma_eepromcount <= to_unsigned(command_counts(count_id),17);
      for packet in 0 to 1 loop
         for i in 0 to command_counts(count_id) - 1 loop
            access_bus(x"0DFFFF02", '0', x"00000001", ACCESS_16BIT);
            assert cart_eeprom_dma = '1' and unsigned(cart_eeprom_count) = command_counts(count_id) and cart_eeprom_din = '1' severity failure;
            if i = command_counts(count_id) - 1 then assert cart_eeprom_last = '1' severity failure;
            else assert cart_eeprom_last = '0' severity failure; end if;
         end loop;
      end loop;
      end loop;
      dma_eepromcount <= to_unsigned(68,17);
      for i in 0 to 67 loop
         access_bus(x"0DFFFF02", '1', x"00000000", ACCESS_16BIT);
         assert mem_bus_din = x"00000001" severity failure;
         if i = 67 then assert cart_eeprom_last = '1' severity failure;
         else assert cart_eeprom_last = '0' severity failure; end if;
      end loop;
      -- CPU/other DMA may run while DMA3 stays pending: stale fullcount
      -- must never classify their requests as DMA3 commands.
      mem_bus_dma3 <= '0'; dma_eepromcount <= to_unsigned(17,17);
      access_bus(x"0DFFFF00", '1', x"00000000", ACCESS_16BIT);
      assert cart_eeprom_dma = '0' and cart_eeprom_last = '1' and unsigned(cart_eeprom_count) = 0 and mem_bus_din = x"00000001" severity failure;
      -- DMA3 abort/inactivity resets partial serial count.
      mem_bus_dma3 <= '1';
      access_bus(x"0DFFFF00", '0', x"00000001", ACCESS_16BIT);
      dma3_active <= '0'; wait for 30 ns; dma3_active <= '1';
      dma_eepromcount <= to_unsigned(1,17);
      access_bus(x"0DFFFF00", '0', x"00000001", ACCESS_16BIT);
      assert cart_eeprom_last = '1' severity failure;
      dma3_active <= '0'; mem_bus_dma3 <= '0';
      -- Existing SD SRAM reads/writes continue through backing memory.
      cart_save_mode <= '0'; before_count := sd_requests;
      access_bus(x"0E000012", '1', x"00000000");
      assert sd_requests = before_count + 1 and mem_bus_din = x"000000A5" severity failure;
      access_bus(x"0E000012", '0', x"0000005A");
      assert bus_out_rnw = '0' and bus_out_din = x"0000005A" and unsigned(bus_out_adr) = 16777216 + 16#12# severity failure;
      -- SD EEPROM keeps its existing emulation; ready polling needs no
      -- physical request and no backing memory access.
      access_bus(x"0DFFFF00", '1', x"00000000", ACCESS_16BIT);
      assert mem_bus_din = x"00000001" severity failure;
      report "PASS cartridge memorymux raw Flash/SRAM, EEPROM DMA3 boundaries and SD-save isolation";
      stop;
      wait;
   end process;
end architecture;
