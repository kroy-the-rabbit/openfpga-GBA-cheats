library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use std.textio.all;
use ieee.std_logic_textio.all;
use work.pProc_bus_gba.all;

entity tb_gba_cart_memorymux is end entity;
architecture test of tb_gba_cart_memorymux is
   signal clk : std_logic := '0';
   signal reset : std_logic := '0';
   signal gb_on : std_logic := '0';
   signal inval : std_logic := '0';
   signal rom_req, rom_done : std_logic := '0';
   signal rom_addr : std_logic_vector(24 downto 0);
   signal rom_first, rom_second : std_logic_vector(31 downto 0) := (others => '0');
   signal rom_wait : natural range 0 to 4 := 0;
   signal rom_word : natural range 0 to 47 := 0;
   signal rom_requests : natural := 0;
   type header_words is array(0 to 47) of std_logic_vector(31 downto 0);
   impure function load_header return header_words is
      file f : text open read_mode is "bmxe-header.hex";
      variable l : line;
      variable h : header_words;
   begin
      for i in h'range loop readline(f,l); hread(l,h(i)); end loop;
      return h;
   end function;
   constant header : header_words := load_header;

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
   signal io_done : std_logic := '1';
   signal io_data : std_logic_vector(31 downto 0) := x"963CA571";
   signal io_writes : natural := 0;
   -- flash-cart halfword traffic
   signal cart_io_req, cart_io_done : std_logic := '0';
   signal cart_io_rnw : std_logic := '1';
   signal cart_io_addr : std_logic_vector(23 downto 0);
   signal cart_io_wdata : std_logic_vector(15 downto 0);
   signal cart_io_rdata : std_logic_vector(15 downto 0) := (others => '0');
   signal cio_reads, cio_writes : natural := 0;
   type cio_log is array(0 to 1) of std_logic_vector(39 downto 0);
   signal cio_last : cio_log := (others => (others => '0'));   -- addr & wdata, newest in 0
   signal cio_wait : natural range 0 to 3 := 0;
   signal mem_bus_host : std_logic := '0';
   signal mem_bus_dma, cart_io_hold : std_logic := '0';
   signal cio_holds : std_logic_vector(1 downto 0) := "00";   -- cart_io_hold at each request, newest in 0
   signal rom_far : boolean := false;   -- a host read of 09E00000's line
begin
   clk <= not clk after 5 ns;
   gb_bus.done <= io_done;
   gb_bus.Dout <= io_data;
   dut : entity work.gba_memorymux
      generic map (is_simu => '1', Softmap_GBA_Gamerom_ADDR => 0,
         Softmap_GBA_WRam_ADDR => 8388608, Softmap_GBA_FLASH_ADDR => 16777216,
         Softmap_GBA_EEPROM_ADDR => 16908288)
      port map (
      clk100 => clk,
      gb_on => gb_on,
      cache_invalidate => inval,
      reset => reset,
      savestate_bus => ss_bus,
      sdram_read_ena => rom_req,
      sdram_read_done => rom_done,
      sdram_read_addr => rom_addr,
      sdram_read_data => rom_first,
      sdram_second_dword => rom_second,
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
      mem_bus_host => mem_bus_host,
      cart_io_req => cart_io_req,
      cart_io_rnw => cart_io_rnw,
      cart_io_addr => cart_io_addr,
      cart_io_wdata => cart_io_wdata,
      cart_io_rdata => cart_io_rdata,
      cart_io_done => cart_io_done,
      cart_io_hold => cart_io_hold,
      mem_bus_dma => mem_bus_dma,
      mem_bus_dma3 => mem_bus_dma3,
      dma3_active => dma3_active,
      dma_eepromcount => dma_eepromcount,
      flash_1m => '0',
      MaxPakAddr => (others => '1'),
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
         rom_done <= '0';
         cart_io_done <= '0';
         if cart_io_req = '1' then
            assert cio_wait = 0 report "Overlapping flash-cart request" severity failure;
            assert cart_save_mode = '1' report "Flash-cart request outside cartridge mode" severity failure;
            cio_wait <= 2;
            cio_last(1) <= cio_last(0);
            cio_last(0) <= cart_io_addr & cart_io_wdata;
            cio_holds <= cio_holds(0) & cart_io_hold;
            if cart_io_rnw = '1' then
               cio_reads <= cio_reads + 1;
               -- Every read answers differently, so a cached answer shows.
               cart_io_rdata <= std_logic_vector(to_unsigned(16#C000# + cio_reads, 16));
            else
               cio_writes <= cio_writes + 1;
            end if;
         elsif cio_wait > 0 then
            cio_wait <= cio_wait - 1;
            if cio_wait = 1 then cart_io_done <= '1'; end if;
         end if;
         if rom_req = '1' then
            rom_far <= unsigned(rom_addr) = 16#780000#;
            assert unsigned(rom_addr) < 48 or unsigned(rom_addr) = 16#780000#
               report "Unexpected ROM request outside header" severity failure;
            assert rom_wait = 0 report "Overlapping ROM request" severity failure;
            if unsigned(rom_addr) < 48 then rom_word <= to_integer(unsigned(rom_addr)); else rom_word <= 0; end if;
            rom_wait <= 3;
            rom_requests <= rom_requests + 1;
         elsif rom_wait > 0 then
            rom_wait <= rom_wait - 1;
            if rom_wait = 1 then
               rom_done <= '1';
               rom_first <= header(rom_word);
               if rom_word mod 2 = 0 then rom_second <= header(rom_word + 1);
               else rom_second <= header(rom_word - 1); end if;
               if rom_far then rom_first <= x"0BADF00D"; rom_second <= x"0BADF00D"; end if;
            end if;
         end if;
         cart_save_done <= cart_save_req;
         cart_eeprom_done <= cart_eeprom_req;
         bus_out_done <= bus_out_ena;
         if cart_save_req = '1' then save_requests <= save_requests + 1; end if;
         if cart_eeprom_req = '1' then eeprom_requests <= eeprom_requests + 1; end if;
         if bus_out_ena = '1' then sd_requests <= sd_requests + 1; end if;
         if gb_bus.ena = '1' and gb_bus.rnw = '0' then io_writes <= io_writes + 1; end if;
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
         -- A request that lands during a cache invalidate waits out the
         -- 1024-entry tag clear before it is served.
         for i in 0 to 1300 loop
            wait until falling_edge(clk);
            if mem_bus_done = '1' then completed := true; exit; end if;
         end loop;
         assert completed report "Memory request did not complete" severity failure;
      end procedure;
      type count_list is array(natural range <>) of natural;
      constant command_counts : count_list := (9, 17, 73, 81);
      variable before_count : natural;
      type access_list is array(natural range <>) of std_logic_vector(1 downto 0);
      constant access_sizes : access_list := (ACCESS_8BIT, ACCESS_16BIT, ACCESS_32BIT);
      variable expected : std_logic_vector(31 downto 0);
   begin
      reset <= '1';
      wait for 100 ns;
      reset <= '0'; gb_on <= '1';
      -- Clear the actual 1024-entry cache before the first miss.
      for i in 0 to 1030 loop wait until falling_edge(clk); end loop;
      -- Cold fills request upper DWORDs first. Subsequent byte/halfword/word
      -- reads cover cache hits, mini-cache hits and every byte lane.
      for i in 0 to 23 loop
         access_bus(std_logic_vector(to_unsigned(16#08000004# + 8*i,32)),
                    '1', x"00000000", ACCESS_32BIT);
         assert mem_bus_din = header(2*i+1) report "Cold odd-DWORD ROM fill mismatch" severity failure;
      end loop;
      assert rom_requests = 24 report "Unexpected header cache fill count" severity failure;
      gb_on <= '0'; wait for 30 ns; gb_on <= '1';
      for i in 0 to 1030 loop wait until falling_edge(clk); end loop;
      for i in 0 to 23 loop
         access_bus(std_logic_vector(to_unsigned(16#08000000# + 8*i,32)),
                    '1', x"00000000", ACCESS_32BIT);
         assert mem_bus_din = header(2*i) report "Cold even-DWORD ROM fill mismatch" severity failure;
      end loop;
      assert rom_requests = 48 report "Unexpected even header cache fill count" severity failure;
      -- rom_patch invalidates the cache when its table changes. A request
      -- that lands while the tags are being cleared must be held and served,
      -- and the line it asks for must be fetched again rather than served
      -- from the dropped tags.
      inval <= '1'; wait until falling_edge(clk); inval <= '0';
      wait until falling_edge(clk);
      access_bus(std_logic_vector(to_unsigned(16#08000010#,32)), '1', x"00000000", ACCESS_32BIT);
      assert mem_bus_din = header(4) report "Read during cache invalidate returned wrong data" severity failure;
      assert rom_requests = 49 report "Invalidated line was served from stale tags" severity failure;
      access_bus(std_logic_vector(to_unsigned(16#08000010#,32)), '1', x"00000000", ACCESS_32BIT);
      assert rom_requests = 49 report "Refetched line did not cache" severity failure;
      for i in 0 to 1030 loop wait until falling_edge(clk); end loop;
      -- The rest of the header is cold again: refill it for the lane sweep.
      for i in 0 to 23 loop
         access_bus(std_logic_vector(to_unsigned(16#08000000# + 8*i,32)), '1', x"00000000", ACCESS_32BIT);
      end loop;
      for size in access_sizes'range loop
         for offset in 0 to 191 loop
            access_bus(std_logic_vector(to_unsigned(16#08000000# + offset,32)),
                       '1', x"00000000", access_sizes(size));
            expected := header(offset / 4);
            case access_sizes(size) is
               when ACCESS_8BIT =>
                  expected := x"000000" & expected(8*(offset mod 4)+7 downto 8*(offset mod 4));
               when ACCESS_16BIT =>
                  if offset mod 4 < 2 then expected := x"0000" & expected(15 downto 0);
                  else expected := x"0000" & expected(31 downto 16); end if;
                  if offset mod 2 = 1 then expected := expected(7 downto 0) & x"0000" & expected(15 downto 8); end if;
               when others => expected := std_logic_vector(rotate_right(unsigned(expected),8*(offset mod 4)));
            end case;
            assert mem_bus_din = expected
               report "ROM header lane/width mismatch offset=" & integer'image(offset) & " size=" & integer'image(size)
               severity failure;
         end loop;
      end loop;
      -- 48 cold fills, one refetch during the invalidate, 23 refills after it.
      assert rom_requests = 72 report "Header cache hits unexpectedly fetched ROM again" severity failure;
      report "PASS BMXE ROM header: 48 cold odd/even fills, 576 lane/width reads through actual cache and memorymux";
      -- An unreadable I/O reply must never leak its speculative data. Check
      -- every lane/width, then immediately follow it with a readable reply.
      for readable in 0 to 1 loop
         if readable = 0 then io_done <= '0'; else io_done <= '1'; end if;
         for size in access_sizes'range loop
            for lane in 0 to 3 loop
               access_bus(std_logic_vector(to_unsigned(16#04000300# + lane, 32)),
                  '1', x"00000000", access_sizes(size));
               expected := (others => '0');
               if readable = 1 then
                  case access_sizes(size) is
                     when ACCESS_8BIT => expected(7 downto 0) := io_data(8*lane+7 downto 8*lane);
                     when ACCESS_16BIT =>
                        if lane < 2 then expected(15 downto 0) := io_data(15 downto 0);
                        else expected(15 downto 0) := io_data(31 downto 16); end if;
                        if lane mod 2 = 1 then expected := expected(7 downto 0) & x"0000" & expected(15 downto 8); end if;
                     when others => expected := std_logic_vector(rotate_right(unsigned(io_data), 8*lane));
                  end case;
               end if;
               assert mem_bus_din = expected report "I/O reply/rotation or unreadable fallback mismatch" severity failure;
            end loop;
         end loop;
         before_count := io_writes;
         access_bus(x"04000300", '0', x"12345678", ACCESS_32BIT);
         assert io_writes = before_count + 1 report "I/O write repeated or lost" severity failure;
      end loop;
      -- This address takes the existing longer I/O wait path.
      access_bus(x"04000090", '1', x"00000000", ACCESS_32BIT);
      assert mem_bus_din = io_data report "Delayed I/O reply mismatch" severity failure;
      report "PASS I/O reply sampling: readable/unreadable lanes, widths, writes and delayed reads";
      -- Flash carts. A ROM-space write reaches the cart as halfwords and
      -- completes only when the cart has taken it.
      access_bus(x"09FE0000", '0', x"0000D200", ACCESS_16BIT);
      assert cio_writes = 1 and cio_last(0) = x"FF0000" & x"D200"
         report "16-bit ROM-space write did not reach the cart" severity failure;
      access_bus(x"08000000", '0', x"87651500", ACCESS_32BIT);
      assert cio_writes = 3 and cio_last(1) = x"000000" & x"1500" and cio_last(0) = x"000001" & x"8765"
         report "32-bit ROM-space write was not two halfwords, low first" severity failure;
      access_bus(x"0A020000", '0', x"0000D200", ACCESS_16BIT);
      assert cio_writes = 4 and cio_last(0) = x"010000" & x"D200"
         report "ROM mirror write did not reach the cart" severity failure;
      -- After a write, 09E00000..09FFFFFF is read from the cart every time.
      before_count := rom_requests;
      access_bus(x"09E00000", '1', x"00000000", ACCESS_16BIT);
      assert cio_last(0)(39 downto 16) = x"F00000" and mem_bus_din = x"0000C000"
         report "Register read did not come from the cart" severity failure;
      access_bus(x"09E00000", '1', x"00000000", ACCESS_16BIT);
      assert mem_bus_din = x"0000C001" report "Register read was served from a cache" severity failure;
      assert cio_holds(0) = '0' and cart_io_hold = '0'
         report "A CPU 16-bit register read asked for a sequential burst" severity failure;
      access_bus(x"09FC0010", '1', x"00000000", ACCESS_32BIT);
      assert cio_last(1)(39 downto 16) = x"FE0008" and cio_last(0)(39 downto 16) = x"FE0009"
         and mem_bus_din = x"C003C002"
         report "32-bit register read was not two halfwords, low first" severity failure;
      assert cio_holds = "11" and cart_io_hold = '0'
         report "A 32-bit read was not held across its halfwords, or stayed held after" severity failure;
      access_bus(x"09FC0013", '1', x"00000000", ACCESS_8BIT);
      assert cio_last(0)(39 downto 16) = x"FE0009" and mem_bus_din = x"000000C0"
         report "8-bit register read took the wrong halfword or lane" severity failure;
      assert cio_reads = 5 and rom_requests = before_count
         report "Register reads touched the ROM cache" severity failure;
      -- A DMA copy from a register is one sequential burst on the cart: the
      -- hold stays up across its reads and drops at the CPU's next access.
      mem_bus_dma <= '1';
      access_bus(x"09FC0012", '1', x"00000000", ACCESS_16BIT);
      assert cio_holds(0) = '1' and cart_io_hold = '1'
         report "DMA register read was not held" severity failure;
      access_bus(x"09FC0014", '1', x"00000000", ACCESS_16BIT);
      assert cio_last(0)(39 downto 16) = x"FE000A" and cio_holds(0) = '1' and cart_io_hold = '1'
         report "DMA burst dropped its hold between words" severity failure;
      mem_bus_dma <= '0';
      access_bus(x"08000010", '1', x"00000000", ACCESS_16BIT);
      assert cart_io_hold = '0' report "CPU access did not end the DMA burst" severity failure;
      -- A write drops both caches: a line already cached, and the 8-byte
      -- line held beside the cache, are fetched again.
      access_bus(x"08000010", '1', x"00000000", ACCESS_16BIT);
      access_bus(x"08000012", '1', x"00000000", ACCESS_16BIT);
      before_count := rom_requests;
      access_bus(x"08000012", '1', x"00000000", ACCESS_16BIT);
      assert rom_requests = before_count report "ROM line was not cached before the write" severity failure;
      access_bus(x"09880000", '0', x"00000200", ACCESS_16BIT);
      access_bus(x"08000012", '1', x"00000000", ACCESS_16BIT);
      assert rom_requests = before_count + 1 and mem_bus_din = x"0000" & header(4)(31 downto 16)
         report "ROM line was served stale after a flash-cart write" severity failure;
      -- The cheat engine's writes stay dropped, and its reads of a register
      -- window come from ROM, never from the cart's register.
      mem_bus_host <= '1'; before_count := cio_writes;
      access_bus(x"09FE0000", '0', x"0000D200", ACCESS_16BIT);
      assert cio_writes = before_count report "Cheat-engine ROM write reached the cartridge" severity failure;
      before_count := cio_reads;
      access_bus(x"09E00000", '1', x"00000000", ACCESS_16BIT);
      assert cio_reads = before_count and mem_bus_din = x"0000F00D"
         report "Cheat-engine read reached a cartridge register" severity failure;
      mem_bus_host <= '0';
      -- A restart forgets the cart was written, and SD mode never forwards.
      gb_on <= '0'; wait for 30 ns; gb_on <= '1';
      for i in 0 to 1030 loop wait until falling_edge(clk); end loop;
      cart_save_mode <= '0'; before_count := cio_writes;
      access_bus(x"09FE0000", '0', x"0000D200", ACCESS_16BIT);
      assert cio_writes = before_count report "SD ROM write reached the cartridge" severity failure;
      cart_save_mode <= '1';
      report "PASS flash cart: ROM-space writes as halfwords, uncached register reads after a write, DMA reads held as one burst, both caches dropped, cheat engine kept off the cart, SD mode untouched";
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
