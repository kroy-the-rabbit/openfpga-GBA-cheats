library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all;   
use ieee.math_real.all;  

library mem;

entity cache is
   generic
   (
      SIZE                     : integer;  -- size of  cache to be cached
      SIZEBASEBITS             : integer;  -- size of memory to be cached
      BITWIDTH                 : integer;
      Softmap_GBA_Gamerom_ADDR : integer   -- count: 8388608  -- 32 Mbyte Data for GameRom 
   );
   port 
   (
      clk               : in  std_logic;
      gb_on             : in  std_logic;
      -- Drop every tag before the next read is served. rom_patch.sv pulses
      -- this when its table changes, so lines cached before the cheat file
      -- arrived are fetched again through the patch, and a flash-cart write
      -- pulses it because the cart may now map different ROM. A request
      -- arriving with or during the clear is held and served afterwards.
      invalidate        : in  std_logic := '0';
                        
      read_enable       : in  std_logic;
      read_addr         : in  std_logic_vector(SIZEBASEBITS-1 downto 0);
      read_data         : out std_logic_vector(BITWIDTH-1 downto 0) := (others => '0');
      read_done         : out std_logic := '0';
      read_full         : out std_logic_vector((BITWIDTH * 2)-1 downto 0) := (others => '0');
      
      mem_read_ena      : out   std_logic := '0';
      mem_read_done     : in    std_logic := '0';
      mem_read_addr     : out   std_logic_vector(24 downto 0) := (others => '0');
      mem_read_data     : in    std_logic_vector(31 downto 0);
      mem_read_data2    : in    std_logic_vector(31 downto 0)
     
   );
end entity;

architecture arch of cache is
  
   constant SIZEBITS     : integer := integer(ceil(log2(real(SIZE))));
   constant ADDRSAVEBITS : integer := SIZEBASEBITS - SIZEBITS;
   
   type tState is
   (
      IDLE,
      CLEARCACHE,
      READCACHE_OUT,
      READCACHE_WAITDONE,
      READCACHE_SECOND
   );
   signal state : tstate := IDLE;
   
   signal up_low_select      : std_logic := '0';
   
   -- memory
   signal memory_addr_a      : natural range 0 to SIZE - 1;
   signal memory_addr_b      : natural range 0 to SIZE - 1;
   signal memory_datain      : std_logic_vector((BITWIDTH*2)-1 downto 0);
   signal memory_dataout     : std_logic_vector((BITWIDTH*2)-1 downto 0);
   signal memory_we          : std_logic := '1';
                             
   -- addr save --  uppermost bit is invalid bit        
   signal addrsave_addr_a    : natural range 0 to SIZE - 1;
   signal addrsave_addr_b    : natural range 0 to SIZE - 1;
   signal addrsave_datain    : std_logic_vector(ADDRSAVEBITS downto 0);
   signal addrsave_dataout   : std_logic_vector(ADDRSAVEBITS downto 0);
   signal addrsave_we        : std_logic := '1';
   signal upperbits          : std_logic_vector(SIZEBASEBITS - SIZEBITS - 1 downto 0);
   
   -- clear cache
   signal clear_counter      : natural range 0 to SIZE - 1;
   
   -- output buffers
   signal read_done_buffer   : std_logic := '0';
   signal inval_pending    : std_logic := '0';
   signal req_pending      : std_logic := '0';
   signal req_addr_l       : std_logic_vector(SIZEBASEBITS-1 downto 0) := (others => '0');
   signal req_now          : std_logic_vector(SIZEBASEBITS-1 downto 0);
   
begin 

   iRamMemory: entity mem.SyncRamDual
   generic map
   (
      DATA_WIDTH => BITWIDTH*2,
      ADDR_WIDTH => SIZEBITS
   )
   port map 
   (
      clk        => clk,
      
      addr_a     => memory_addr_a,
      datain_a   => (memory_dataout'range => '0'),
      dataout_a  => memory_dataout,
      we_a       => '0',
      re_a       => '1',
                 
      addr_b     => memory_addr_b,
      datain_b   => memory_datain,
      dataout_b  => open,
      we_b       => memory_we,
      re_b       => '0'    
   );
   
   iRamaddrsave: entity mem.SyncRamDual
   generic map
   (
      DATA_WIDTH => ADDRSAVEBITS + 1,
      ADDR_WIDTH => SIZEBITS
   )
   port map 
   (
      clk        => clk,    
      
      addr_a     => addrsave_addr_a,
      datain_a   => (addrsave_dataout'range => '0'),
      dataout_a  => addrsave_dataout,
      we_a       => '0',
      re_a       => '1',
                 
      addr_b     => addrsave_addr_b,
      datain_b   => addrsave_datain,
      dataout_b  => open,
      we_b       => addrsave_we,
      re_b       => '0'       
   );
   
   memory_addr_a    <= to_integer(unsigned(read_addr(SIZEBITS downto 1)));
   addrsave_addr_a  <= to_integer(unsigned(read_addr(SIZEBITS downto 1)));
   
   read_done_buffer <= '1' when state = READCACHE_OUT and (addrsave_dataout = '0' & upperbits) else '0';
   -- A live request and one held through a clear never coincide.
   req_now          <= read_addr when read_enable = '1' else req_addr_l;
   read_data        <= memory_dataout(31 downto 0) when up_low_select = '0' else memory_dataout(63 downto 32);
   read_full        <= memory_dataout;
   
   process (clk)
   begin
      if rising_edge(clk) then
         
         memory_we         <= '0';
         addrsave_we       <= '0';
         
         mem_read_ena      <= '0';

         -- A clear already running covers an invalidate that lands during
         -- it: no read is served until it ends, so nothing it has already
         -- dropped can be refilled. A burst of flash-cart writes costs one
         -- clear, not one per write.
         if (invalidate = '1' and state /= CLEARCACHE) then
            inval_pending <= '1';
         end if;

         if (gb_on = '0') then
            state         <= CLEARCACHE;
            clear_counter <= 0;
            req_pending   <= '0';
            inval_pending <= '0';
         else

            case(state) is
            
               when CLEARCACHE =>
                  if (read_enable = '1') then
                     req_pending <= '1';
                     req_addr_l  <= read_addr;
                  end if;
                  if (clear_counter < SIZE - 1) then
                     clear_counter <= clear_counter + 1;
                  else
                     state          <= IDLE;
                  end if;
                  addrsave_addr_b <= clear_counter;
                  addrsave_datain <= (others => '1');
                  addrsave_we     <= '1';
            
               when IDLE =>
                  -- The clear goes first. A read that follows a flash-cart
                  -- write must not be served from a tag the write made stale.
                  if (inval_pending = '1') then
                     inval_pending   <= '0';
                     state           <= CLEARCACHE;
                     clear_counter   <= 0;
                     if (read_enable = '1') then
                        req_pending <= '1';
                        req_addr_l  <= read_addr;
                     end if;
                  elsif (read_enable = '1' or req_pending = '1') then
                     req_pending     <= '0';
                     mem_read_addr   <= std_logic_vector(to_unsigned(Softmap_GBA_Gamerom_ADDR, 25) + unsigned(req_now));
                     memory_addr_b   <= to_integer(unsigned(req_now(SIZEBITS downto 1)));
                     addrsave_addr_b <= to_integer(unsigned(req_now(SIZEBITS downto 1)));
                     addrsave_datain <= '0' & req_now(SIZEBASEBITS-1 downto SIZEBITS);
                     upperbits       <= req_now(SIZEBASEBITS-1 downto SIZEBITS);
                     up_low_select   <= req_now(0);
                     state           <= READCACHE_OUT;
                  end if;
                  
   
               when READCACHE_OUT =>
                  if (addrsave_dataout = '0' & upperbits) then
                     state             <= IDLE;
                  else
                     state             <= READCACHE_WAITDONE;
                     mem_read_ena      <= '1';
                  end if;
                  
               when READCACHE_WAITDONE =>
                  if (mem_read_done = '1') then
                     state <= READCACHE_SECOND;
                     if (up_low_select = '0') then
                        memory_datain(31 downto 0)  <= mem_read_data;
                     else
                        memory_datain(63 downto 32) <= mem_read_data;
                     end if;
                  end if;
                  
               when READCACHE_SECOND =>
                  state       <= IDLE;
                  addrsave_we <= '1';         
                  memory_we   <= '1';         
                  if (up_low_select = '1') then
                     memory_datain(31 downto 0)  <= mem_read_data2;
                  else
                     memory_datain(63 downto 32) <= mem_read_data2;
                  end if;
   
            end case;  
            
         end if;

      end if;
   end process;
   
   read_done  <= read_done_buffer; 
   
end architecture;




























