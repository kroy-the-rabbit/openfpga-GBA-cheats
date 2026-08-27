// gba_cart_controller.sv
//
// GBA cartridge bus controller for Analogue Pocket (HAN project).
//
// Provides a transparent bridge between the GBA core and a physical GBA
// cartridge in the Pocket slot:
//   - ROM reads  : 16-bit, CS1#, read-only   (used by rom_source_mux)
//   - Save access: 8-bit SRAM/Flash via CS2# (Flash commands are forwarded
//                  to the cart chip, which executes them itself)
//   - EEPROM     : bit-serial via ROMCS#/A23/D0 (per-bit forward, the real
//                  EEPROM chip executes the command itself). GBATEK
//                  "Pin-Outs": EEPROM pins 1..8 connect to ROMCS, RD, WR,
//                  AD0, GND, GND, A23, VDD — the chip-select is ROMCS
//                  (Pin 5 / CS1#), NOT CS2# (Pin 30).
//   - GPIO access: 16-bit R/W at 0x080000C4..0x080000C8 (RTC, solar, gyro,
//                  rumble cart hardware). These are plain ROM-area bus
//                  accesses: CS1# falls to latch the halfword address, then
//                  RD#/WR# pulse with data on D3..D0. The register block is
//                  inside the cart's ROM chip, so no protocol is emulated -
//                  we only drive the bus cycles.
//
// Timing is modeled on the measured cartridge protocol from
//   https://github.com/jojolebarjos/gba-cartridge
// and on GBATEK (WAITCNT defaults). All wait-state constants remain
// conservative placeholders and MUST be tuned on real carts.
//
// PHI generation: clk_sys ~100.66 MHz / PHI_DIV = 16.78 MHz.

`default_nettype none

module gba_cart_controller #(
    parameter integer PHI_DIV_16M = 6,  // clk_sys / PHI for 16.78MHz PHI output
    // Wait-state placeholders, in clk_sys (100 MHz) cycles.
    // GBATEK default WAITCNT=4317h: ROM N/S = 3/1 waits (access = 1+waits
    // GBA cycles); SRAM = 8 waits; EEPROM WS2 = 8/8 waits. One GBA cycle
    // ~= 6 clk_sys cycles, so ROM non-sequential ~= 4*6=24 clk_sys cycles
    // and SRAM ~= 9*6=54 clk_sys cycles. Tune on real carts.
    parameter integer ROM_WAIT   = 24,  // clk_sys cycles per 16-bit ROM read
    parameter integer SAVE_WAIT  = 54,  // clk_sys cycles per 8-bit SRAM/Flash access
    parameter integer ADDR_SETUP = 4,   // clk_sys cycles driving address
    // GPIO write timing (deliberately close to a real GBA host, not the long
    // SRAM/Flash timing). A real GBA ROM access is ~5 GBA cycles (~300 ns):
    // CS# low -> 1 cycle -> WR# low pulse -> WR# high -> CS# high. The
    // ROM-chip GPIO block is a synchronous state machine inside the mask ROM;
    // an over-long CS#-low / WR#-low window (e.g. >1 us) can exceed its
    // internal timeout and the register write is silently dropped. These
    // constants are independent of ADDR_SETUP/SAVE_WAIT on purpose.
    parameter integer GPIO_ADDR_HOLD = 8,   // CS# low, address still driven
                                             // (~80 ns; real carts need
                                             // >1 GBA cycle address hold)
    parameter integer GPIO_DATA_SETUP = 4,  // data driven, WR# high (~40 ns)
    parameter integer GPIO_WR_LOW = 16,     // WR# low pulse (~160 ns)
    parameter integer GPIO_DONE_HOLD = 8,   // data hold after CS# rises
    // Inter-access recovery time in clk_sys cycles (GPIO only).
    // Measured on a real cart: the ROM-chip GPIO registers latch a write a
    // beat late -- a read immediately after a write returns the PREVIOUS
    // value (W5->R0, W7->R5, WF->R7), and RTC bit-banging fails. Inserting
    // a ~14ms delay between accesses makes the read-back correct and the
    // S3511 returns a valid status byte (0x40). 8us was NOT enough on real
    // hardware (still all-FF / FAIL); the ROM-chip GPIO latch apparently
    // needs much more. 10000 cycles @100MHz = 100us per access: a 7-byte
    // RTC read takes ~5ms, fine at boot. The S3511 tSCK spec wants
    // >= 0.5-5us pulses, so 100us is safely inside the rating.
    parameter integer GPIO_RECOVER = 10000,
    // insideGadgets GBxCartRead Part 3 measured the real GBA EEPROM bit
    // clock at ~600 ns full period (~300 ns half) on a logic analyser.
    // HALF_CYCLE=50 gives ~620 ns bit period, matching the real bus.
    parameter integer EEPROM_HALF_CYCLE = 50, // clk_sys cycles per RD#/WR# half pulse
    parameter integer EEPROM_ADDR_SETUP = 16, // clk_sys cycles A23/D0 stable
                                             // before CS# falls (EEPROM)
    // CS#/CS2# stay low for this many clk_sys cycles after WR#/RD# rise.
    // 32 cycles = 320 ns @100 MHz. Real Flash needs 30-50 ns write recovery;
    // the ROM-chip GPIO registers need CS#-low time to process the write and
    // valid data at/after the CS# rising edge (see S_DONE hold phases).
    parameter integer RELEASE_DELAY = 32,
    parameter integer EEPROM_SESS_TIMEOUT = 1024, // clk_sys cycles without EEPROM
                                                  // access before releasing CS2#/A23
    parameter integer RESET_LEN  = 4096
) (
    input  wire        clk,
    input  wire        reset_n,

    // ---- PHI terminal control (WAITCNT bit12..11, from gba_top) ----
    // 0 = disabled (pin idle high, GBA default), 1 = 4.19MHz, 2 = 8.38MHz,
    // 3 = 16.78MHz. PHI is only consumed by add-on chips that take a clock
    // (e.g. the Yoshi tilt-sensor ADC). The GPIO registers inside the ROM
    // chip do NOT need PHI: GBATEK shows Warioware Twisted's gyro/rumble
    // running with WAITCNT=45B7h (PHI=Off). (The "9853/9854" part numbers
    // are 4K/64K EEPROM chips, not GPIO/RTC.)
    input  wire [1:0]  phi_sel,

    // ---- Pocket cartridge slot (from core_top) ----
    inout  wire [7:0]  cart_tran_bank2,    // GBA AD[15:8]
    output wire        cart_tran_bank2_dir,
    inout  wire [7:0]  cart_tran_bank3,    // GBA AD[7:0]
    output wire        cart_tran_bank3_dir,
    inout  wire [7:0]  cart_tran_bank1,    // GBA A[23:16]
    output wire        cart_tran_bank1_dir,
    inout  wire [7:4]  cart_tran_bank0,    // [7]=PHI# [6]=WR# [5]=RD# [4]=CS1#
    output wire        cart_tran_bank0_dir,
    inout  wire        cart_tran_pin30,    // GBA CS2#/RES#
    output wire        cart_tran_pin30_dir,
    output wire        cart_pin30_pwroff_reset,
    inout  wire        cart_tran_pin31,    // GBA IRQ/DRQ (input, unused)
    output wire        cart_tran_pin31_dir,

    // ---- ROM read interface (sdram_pocket style, DWORD addresses) ----
    input  wire        rd_req,
    input  wire [24:0] rd_addr,
    output reg  [31:0] rd_data,
    output reg  [31:0] rd_data_second,
    output reg         rd_ready,

    // ---- Save access (SRAM/Flash, from core_top save_router) ----
    input  wire        save_req,
    input  wire [16:0] save_addr,          // byte offset within save region
    input  wire        save_rnw,           // 1 = read, 0 = write
    input  wire [7:0]  save_din,
    output reg  [7:0]  save_dout,
    output reg         save_done,

    // ---- EEPROM bit access (from gba_top, cart mode) ----
    input  wire        eeprom_req,
    input  wire        eeprom_rnw,         // 1 = read, 0 = write
    input  wire        eeprom_din,         // write data bit (D0)
    input  wire        eeprom_dma,         // 1 = bit access via DMA3 burst,
                                           // 0 = standalone CPU LDRH/STRH
                                           // (write-complete ready polling)
    output reg         eeprom_dout,        // read data bit (D0)
    output reg         eeprom_done,

    // ---- GPIO access (from gba_top, cart mode) ----
    input  wire        gpio_req,
    input  wire        gpio_rnw,           // 1 = read, 0 = write
    input  wire [1:0]  gpio_addr,          // 0..2 -> 0x080000C4..0x080000C8
    input  wire [3:0]  gpio_din,           // write data (D3..D0)
    output reg  [3:0]  gpio_dout,          // read data (D3..D0)
    output reg         gpio_done,
    // GPIO write-timing mode select (0..5), written by the diag ROM via
    // 0x400030A so one bitstream can sweep several write timings:
    //   0: addr-hold 8, data-setup 4, WR#-low 16 (default)
    //   1: addr-hold 2, data-setup 2, WR#-low 16
    //   2: addr-hold 16, data-setup 16, WR#-low 54 (long, SRAM-style)
    //   3: addr-hold 8, data switches with WR# falling (no setup)
    //   4: addr-hold 200, data-setup 100, WR#-low 255 (~6us per access,
    //      slow enough to exceed the S3511 tSCK minimum pulse)
    //   5: addr-hold 255, data-setup 200, WR#-low 255 (~12us, diagnostic)
    input  wire [2:0]  gpio_timing_mode,
    // Runtime GPIO inter-access recovery override (cycles @100MHz, 0 =
    // use the GPIO_RECOVER parameter). Written by the diag ROM via
    // 0x4000310 so the settle time can be swept on real carts without
    // rebuilding the bitstream.
    input  wire [13:0] gpio_recover_set,

    // ---- status / debug ----
    // GPIO diagnostic byte (read by the diag ROM via 0x4000308 bit15-8):
    //   bit0: GPIO request entered S_GPIO_A
    //   bit1: CS1# went low for this GPIO access
    //   bit2: WR# low pulse issued (GPIO write)
    //   bit3: GPIO read sampled (RD# low phase)
    //   bit4: PHI enabled (WAITCNT bit11-12 != 0)
    //   bit5: PHI pin current level (live)
    //   bit6: GPIO write data driven on AD[7:0]
    //   bit7: GPIO READ request entered controller (S_GPIO_A with rnw=1)
    output reg  [7:0]  gpio_diag,
    output reg         cart_present,
    output reg  [7:0]  err_count
);

    // ------------------------------------------------------------------
    // PHI generation (bank0[7])
    // ------------------------------------------------------------------
    // WAITCNT bit12..11 selects the PHI frequency. clk_sys ~100.66 MHz:
    //   00 = disabled (idle high), 01 = 4.19MHz (div 24),
    //   10 = 8.38MHz (div 12),      11 = 16.78MHz (div 6).
    wire [4:0] phi_div =
        (phi_sel == 2'd1) ? 5'd24 :
        (phi_sel == 2'd2) ? 5'd12 :
        (phi_sel == 2'd3) ? PHI_DIV_16M[4:0] : 5'd1;
    reg [4:0] phi_cnt;
    wire phi_enable = (phi_sel != 2'd0);
    wire phi = phi_enable && (phi_cnt < (phi_div >> 1));

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            phi_cnt <= 5'd0;
        else if (!phi_enable || phi_div <= 1)
            phi_cnt <= 5'd0;
        else if (phi_cnt == phi_div - 1)
            phi_cnt <= 5'd0;
        else
            phi_cnt <= phi_cnt + 1'b1;
    end

    // ------------------------------------------------------------------
    // Cartridge power-on reset (RES# low for RESET_LEN cycles)
    // ------------------------------------------------------------------
    reg [11:0] reset_cnt;
    reg        res_n;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            reset_cnt <= 12'd0;
            res_n     <= 1'b0;
        end else if (reset_cnt == RESET_LEN - 1) begin
            reset_cnt <= reset_cnt;      // saturate
            res_n     <= 1'b1;
        end else begin
            reset_cnt <= reset_cnt + 1'b1;
            res_n     <= 1'b0;
        end
    end

    // ------------------------------------------------------------------
    // Main access state machine
    // ------------------------------------------------------------------
    localparam S_IDLE      = 4'd0;
    localparam S_ROM_CS    = 4'd1;   // drive address, then assert CS1#
    localparam S_ROM_DATA  = 4'd2;   // release AD, strobe RD#, sample 16-bit
    localparam S_ROM_DONE  = 4'd3;
    localparam S_SRAM      = 4'd4;   // 8-bit SRAM/Flash byte access (CS2#)
    localparam S_SRAM_W    = 4'd5;   // write strobe phase
    localparam S_EEPROM    = 4'd6;   // bit-serial EEPROM forward
    localparam S_GPIO_A    = 4'd7;   // GPIO 16-bit: address phase
    localparam S_GPIO_R    = 4'd8;   // GPIO read data phase
    localparam S_GPIO_W    = 4'd9;   // GPIO write data phase
    localparam S_DONE      = 4'd10;
    localparam S_EEPROM_RESET = 4'd11; // /CS high pulse between EEPROM
                                       // command burst and data burst
    localparam S_GPIO_DONE = 4'd12;  // GPIO access completion: CS#-low write
                                     // recovery, CS# rise with data hold,
                                     // then bus release (host-like timing)
    localparam S_GPIO_RECOVER = 4'd13; // GPIO-only settle time between
                                       // accesses (see GPIO_RECOVER)

    reg [3:0]  state;
    reg [1:0]  word_idx;
    reg [24:0] byte_addr;
    reg [13:0] acc_cnt;
    reg [15:0] words [0:3];
    reg [16:0] save_addr_r;
    reg        save_is_write;
    reg [15:0] gpio_abs_addr;      // 0x00C4 + {gpio_addr,1'b0}
    reg [3:0]  gpio_din_r;
    reg        gpio_rnw_r;         // latched R/W direction at request accept
    // Selected GPIO write timing (combinational from gpio_timing_mode)
    reg [7:0]  gpio_wr_addr_hold, gpio_wr_data_setup, gpio_wr_low;
    // EEPROM session: GBATEK requires /CS=LOW and A23=HIGH throughout the
    // whole DMA3 transfer, not just per-bit. We keep the chip selected for a
    // short timeout after the last bit; the next bit (DMA continues) reuses
    // the open session, and the session closes once DMA pauses.
    reg        eeprom_sess;
    reg [9:0]  eeprom_sess_cnt;
    // Latched per-access flag: 1 = this bit was requested by a DMA3 burst
    // (keep /CS low across the burst), 0 = standalone CPU access (polling,
    // each access is its own /CS low-high cycle so the cart chip updates its
    // busy/ready status on the /CS rising edge).
    reg        eeprom_dma_r;
    // Direction of the last EEPROM bit of the current session. The game
    // writes the read/write command as a burst of write bits (rnw=0) and then
    // reads data as a burst of read bits (rnw=1). The rnw transition means
    // the command burst is over: real carts latch the command when /CS rises,
    // so we must pulse /CS high before starting the read burst.
    reg        eeprom_rnw_prev;

    // Bus output registers
    reg [7:0]  out_bank1, out_bank2, out_bank3;
    reg        out_bank1_dir, out_bank2_dir, out_bank3_dir;
    reg        rd_n, cs_n, cs2_n, wr_n;

    wire [23:0] word_addr = (byte_addr >> 1) + word_idx;

    // GPIO write timing sweep (see gpio_timing_mode). Combinational so the
    // diag ROM can switch modes between accesses without reconfiguring.
    always @(*) begin
        case (gpio_timing_mode)
            3'd1: begin gpio_wr_addr_hold = 8'd2;   gpio_wr_data_setup = 8'd2;   gpio_wr_low = 8'd16;  end
            3'd2: begin gpio_wr_addr_hold = 8'd16;  gpio_wr_data_setup = 8'd16;  gpio_wr_low = 8'd54;  end
            3'd3: begin gpio_wr_addr_hold = 8'd8;   gpio_wr_data_setup = 8'd0;   gpio_wr_low = 8'd16;  end
            3'd4: begin gpio_wr_addr_hold = 8'd200; gpio_wr_data_setup = 8'd100; gpio_wr_low = 8'd255; end
            3'd5: begin gpio_wr_addr_hold = 8'd255; gpio_wr_data_setup = 8'd200; gpio_wr_low = 8'd255; end
            default: begin gpio_wr_addr_hold = 8'd8; gpio_wr_data_setup = 8'd4; gpio_wr_low = 8'd16; end
        endcase
    end

    // Effective inter-access recovery: runtime register wins, otherwise the
    // compiled-in GPIO_RECOVER parameter. 14 bits covers 0..16383 cycles
    // (~164us @100MHz); the register counter must be this wide too so the
    // wait can never wrap (an 8-bit acc_cnt silently turned 800/10000 into
    // a wrong or stuck recovery).
    wire [13:0] gpio_recover_wait = gpio_recover_set ? gpio_recover_set : GPIO_RECOVER[13:0];

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state           <= S_IDLE;
            word_idx        <= 2'd0;
            byte_addr       <= 25'd0;
            acc_cnt         <= 8'd0;
            rd_data         <= 32'd0;
            rd_data_second  <= 32'd0;
            rd_ready        <= 1'b0;
            save_dout       <= 8'd0;
            save_done       <= 1'b0;
            save_addr_r     <= 17'd0;
            save_is_write   <= 1'b0;
            eeprom_dout     <= 1'b0;
            eeprom_done     <= 1'b0;
            gpio_abs_addr   <= 16'd0;
            gpio_din_r      <= 4'd0;
            gpio_rnw_r      <= 1'b0;
            gpio_dout       <= 4'd0;
            gpio_done       <= 1'b0;
            gpio_diag       <= 8'd0;
            eeprom_sess     <= 1'b0;
            eeprom_sess_cnt <= 10'd0;
            eeprom_rnw_prev <= 1'b1;
            eeprom_dma_r    <= 1'b1;
            out_bank1       <= 8'h00;
            out_bank2       <= 8'h00;
            out_bank3       <= 8'h00;
            out_bank1_dir   <= 1'b0;
            out_bank2_dir   <= 1'b0;
            out_bank3_dir   <= 1'b0;
            rd_n            <= 1'b1;
            cs_n            <= 1'b1;
            cs2_n           <= 1'b1;
            wr_n            <= 1'b1;
            cart_present    <= 1'b0;
            err_count       <= 8'd0;
            words[0]        <= 16'd0;
            words[1]        <= 16'd0;
            words[2]        <= 16'd0;
            words[3]        <= 16'd0;
        end else begin
            rd_ready  <= 1'b0;
            save_done <= 1'b0;
            eeprom_done <= 1'b0;
            gpio_done <= 1'b0;
            // Live PHI status for the diag ROM (0x4000308 bit15-8):
            // bit4 = enabled by WAITCNT, bit5 = PHYSICAL pin level read back
            // from the slot. If an external driver (Pocket slot circuitry)
            // fights our output, the read-back will show it instead of the
            // internally generated phi.
            gpio_diag[5] <= cart_tran_bank0[7];
            gpio_diag[4] <= phi_enable;

            case (state)
                S_IDLE: begin
                    rd_n  <= 1'b1;
                    cs_n  <= 1'b1;
                    wr_n  <= 1'b1;
                    out_bank2_dir <= 1'b0;
                    out_bank3_dir <= 1'b0;

                    if (eeprom_sess) begin
                        // GBATEK: /CS must stay LOW and A23 HIGH for the whole
                        // DMA3 transfer. Keep the session open while bits keep
                        // arriving; close it after EEPROM_SESS_TIMEOUT cycles
                        // of inactivity (DMA finished / paused).
                        cs2_n         <= 1'b0;
                        cs_n          <= 1'b0;    // ROMCS stays low (EEPROM /CS)
                        cs2_n         <= 1'b1;    // pin30 stays RES# high
                        out_bank1     <= 8'h80;   // A23 = 1
                        out_bank1_dir <= 1'b1;
                        if (eeprom_sess_cnt == EEPROM_SESS_TIMEOUT - 1) begin
                            eeprom_sess <= 1'b0;   // release next cycle
                        end else begin
                            eeprom_sess_cnt <= eeprom_sess_cnt + 1'b1;
                        end
                    end else begin
                        cs_n          <= 1'b1;
                        cs2_n         <= 1'b1;
                        out_bank1_dir <= 1'b0;
                    end

                    if (rd_req) begin
                        eeprom_sess     <= 1'b0;   // other access: close session
                        byte_addr <= {rd_addr, 2'b00};
                        word_idx  <= 2'd0;
                        acc_cnt   <= 8'd0;
                        state     <= S_ROM_CS;
                    end else if (save_req) begin
                        eeprom_sess     <= 1'b0;
                        save_addr_r   <= save_addr;
                        save_is_write <= ~save_rnw;
                        acc_cnt       <= 8'd0;
                        state         <= S_SRAM;
                    end else if (eeprom_req) begin
                        eeprom_sess     <= 1'b1;   // (re)open EEPROM session
                        eeprom_sess_cnt <= 10'd0;
                        eeprom_dma_r    <= eeprom_dma;
                        if (eeprom_sess && (eeprom_rnw != eeprom_rnw_prev)) begin
                            // Session in progress and the bit direction
                            // flipped (write burst -> read burst): the
                            // command burst is complete. Pulse /CS high so the
                            // cart chip latches the command (read) or starts
                            // programming (write -> ready polling), then
                            // start the read burst with /CS low again.
                            acc_cnt <= 8'd0;
                            state   <= S_EEPROM_RESET;
                        end else begin
                            acc_cnt <= 8'd0;
                            state   <= S_EEPROM;
                        end
                        eeprom_rnw_prev <= eeprom_rnw;
                    end else if (gpio_req) begin
                        eeprom_sess     <= 1'b0;
                        // Halfword address: 0x080000C4..0x080000C8 (byte) >> 1
                        // = 0x04000062..0x04000064. The cartridge bus always
                        // carries halfword addresses for ROM-space access.
                        gpio_abs_addr <= 16'h0062 + {14'd0, gpio_addr};
                        gpio_din_r    <= gpio_din;
                        gpio_rnw_r    <= gpio_rnw;   // latch R/W with the request
                        acc_cnt       <= 8'd0;
                        state         <= S_GPIO_A;
                    end
                end

                // ---- ROM: 16-bit read, CS# falling edge latches address ----
                // Per jojolebarjos/gba-cartridge:
                //   address must be driven before CS# falls (latched on ~CS edge)
                //   data sampled before ~RD rising edge; ~RD rising increments
                //   the latched address internally, but we re-drive it anyway.
                S_ROM_CS: begin
                    // Address setup phase: drive full 24-bit address, CS# high.
                    out_bank1     <= word_addr[23:16];
                    out_bank2     <= word_addr[15:8];
                    out_bank3     <= word_addr[7:0];
                    out_bank1_dir <= 1'b1;
                    out_bank2_dir <= 1'b1;
                    out_bank3_dir <= 1'b1;
                    rd_n          <= 1'b1;
                    wr_n          <= 1'b1;
                    cs_n          <= 1'b1;        // default: keep CS# high
                    if (acc_cnt < ADDR_SETUP - 1) begin
                        acc_cnt <= acc_cnt + 1'b1;
                    end else begin
                        cs_n    <= 1'b0;          // ~CS falling edge latches address
                        acc_cnt <= 8'd0;
                        state   <= S_ROM_DATA;
                    end
                end

                S_ROM_DATA: begin
                    if (acc_cnt < ADDR_SETUP) begin
                        // CS# has fallen; hold the address on AD[15:0] for the
                        // latch hold time before releasing it to data.
                        rd_n <= 1'b1;
                        acc_cnt <= acc_cnt + 1'b1;
                    end else if (acc_cnt == ADDR_SETUP) begin
                        // Release AD bus (data comes from cart on AD[15:0])
                        // and start the read strobe.
                        out_bank2_dir <= 1'b0;
                        out_bank3_dir <= 1'b0;
                        rd_n          <= 1'b0;   // ~RD falling edge fetches data
                        acc_cnt       <= acc_cnt + 1'b1;
                    end else if (acc_cnt < ADDR_SETUP + ROM_WAIT - 1) begin
                        rd_n <= 1'b0;
                        acc_cnt <= acc_cnt + 1'b1;
                    end else begin
                        // Sample while ~RD is still low (data stable; the cart
                        // drives AD during the RD# low phase).
                        words[word_idx] <= {cart_tran_bank2, cart_tran_bank3};
                        rd_n            <= 1'b1;
                        cs_n            <= 1'b1;  // end this word's transaction
                        acc_cnt         <= 8'd0;
                        if (word_idx == 2'd3) begin
                            state <= S_ROM_DONE;
                        end else begin
                            word_idx <= word_idx + 1'b1;
                            state    <= S_ROM_CS;   // next word: re-drive address
                        end
                    end
                end

                S_ROM_DONE: begin
                    rd_n  <= 1'b1;
                    cs_n  <= 1'b1;
                    out_bank1_dir <= 1'b0;
                    out_bank2_dir <= 1'b0;
                    out_bank3_dir <= 1'b0;
                    rd_data        <= {words[1], words[0]};
                    rd_data_second <= {words[3], words[2]};
                    cart_present   <= 1'b1;
                    rd_ready       <= 1'b1;
                    state          <= S_IDLE;
                end

                // ---- SRAM / Flash byte access (CS2#) ----
                // Real GBA SRAM protocol: 16-bit address on AD[15:0],
                // 8-bit data on A[23:16] (bank1), selected by ~CS2.
                S_SRAM: begin
                    // Address phase: drive AD[15:0]. CS2# falls only after the
                    // address has been stable for >=2 cycles. For writes the
                    // data on A[23:16] is pre-driven from the first cycle so
                    // it is stable >=4 cycles before WR# falls. Real Flash
                    // samples address+data on the WE# falling edge and needs
                    // ~30-50ns data setup; SRAM samples on the WE# rising edge
                    // so it tolerates the earlier data too.
                    out_bank2     <= save_addr_r[15:8];
                    out_bank3     <= save_addr_r[7:0];
                    out_bank2_dir <= 1'b1;
                    out_bank3_dir <= 1'b1;
                    cs_n          <= 1'b1;

                    if (acc_cnt < ADDR_SETUP) begin
                        // CS2# falls only after the address has settled
                        if (acc_cnt >= 2) cs2_n <= 1'b0;
                        else              cs2_n <= 1'b1;
                        if (save_is_write) begin
                            out_bank1     <= save_din;
                            out_bank1_dir <= 1'b1;
                        end else begin
                            out_bank1_dir <= 1'b0;   // data bus input for read
                        end
                        rd_n <= 1'b1;   // keep strobes high during address setup
                        wr_n <= 1'b1;
                        acc_cnt <= acc_cnt + 1'b1;
                    end else if (acc_cnt == ADDR_SETUP) begin
                        // One extra cycle so address+data are fully stable,
                        // then start the strobe.
                        if (save_is_write) begin
                            wr_n <= 1'b0;
                            rd_n <= 1'b1;
                        end else begin
                            rd_n <= 1'b0;
                            wr_n <= 1'b1;
                        end
                        acc_cnt <= acc_cnt + 1'b1;
                    end else if (save_is_write) begin
                        // Write strobe phase
                        rd_n <= 1'b1;
                        if (acc_cnt == ADDR_SETUP + SAVE_WAIT - 1) begin
                            wr_n  <= 1'b1;
                            acc_cnt <= 8'd0;
                            state   <= S_DONE;
                        end else begin
                            acc_cnt <= acc_cnt + 1'b1;
                        end
                    end else begin
                        // Read strobe phase: sample data on A[23:16]
                        out_bank1_dir <= 1'b0;
                        wr_n          <= 1'b1;
                        if (acc_cnt == ADDR_SETUP + SAVE_WAIT - 1) begin
                            rd_n      <= 1'b1;
                            save_dout <= cart_tran_bank1;
                            acc_cnt   <= 8'd0;
                            state     <= S_DONE;
                        end else begin
                            acc_cnt <= acc_cnt + 1'b1;
                        end
                    end
                end

                // ---- EEPROM: bit-serial forward (CS2#=ROMCS, A23=high,
                //      RD#/WR# = bit clock, D0 = data) ----
                // Per GBATEK "GBA Cart Backup EEPROM": during the whole DMA
                // transfer the cart sees /CS=LOW and A23=HIGH, and each bit is
                // driven by one 16-bit DMA access (RD# for reads, WR# for
                // writes), data on AD0. /CS is ROMCS (Pin 5), not CS2#.
                // We forward one bit per request.
                S_EEPROM: begin
                    // A23 (=bank1[7]) stays HIGH during the whole transfer,
                    // as on the real GBA bus when addressing 0x0Dxxxxxx.
                    out_bank1     <= 8'h80;
                    out_bank1_dir <= 1'b1;
                    out_bank2_dir <= 1'b0;
                    cs2_n         <= 1'b1;   // pin30 stays RES# high
                    if (eeprom_rnw) begin
                        out_bank3_dir <= 1'b0;
                        wr_n          <= 1'b1;
                    end else begin
                        // Write bit: D0 driven from the very first cycle so it
                        // is stable long before WR# falls.
                        out_bank3     <= {7'b0, eeprom_din};
                        out_bank3_dir <= 1'b1;
                        rd_n          <= 1'b1;
                    end

                    if (acc_cnt < EEPROM_ADDR_SETUP) begin
                        // Address/data setup: A23 (+D0) stable.
                        // First bit of a new session: CS# starts high, then
                        // falls. Subsequent bits of the same DMA transfer:
                        // CS# MUST stay low - GBATEK requires /CS=LOW and
                        // A23=HIGH throughout the whole transfer; raising CS#
                        // between bits resets the serial EEPROM chip.
                        // eeprom_sess here is the OLD value: 0 on the first
                        // request, 1 on later requests of the same session.
                        cs_n  <= ~eeprom_sess;
                        rd_n  <= 1'b1;
                        wr_n  <= 1'b1;
                        acc_cnt <= acc_cnt + 1'b1;
                    end else if (acc_cnt == EEPROM_ADDR_SETUP) begin
                        // CS# falls with A23/D0 already stable (first bit),
                        // or simply stays low (session in progress).
                        cs_n  <= 1'b0;
                        rd_n  <= 1'b1;
                        wr_n  <= 1'b1;
                        acc_cnt <= acc_cnt + 1'b1;
                    end else if (acc_cnt < EEPROM_ADDR_SETUP + 2) begin
                        // Hold CS# low one cycle before starting the bit pulse
                        rd_n  <= 1'b1;
                        wr_n  <= 1'b1;
                        acc_cnt <= acc_cnt + 1'b1;
                    end else if (eeprom_rnw) begin
                        // Read bit: RD# low pulse, then sample D0 immediately
                        // after the RD# rising edge. insideGadgets' logic
                        // analyser capture reads AD0 right after RD goes high
                        // (the chip holds the bit briefly past the edge);
                        // waiting hundreds of ns reads the tri-stated bus.
                        if (acc_cnt < EEPROM_ADDR_SETUP + EEPROM_HALF_CYCLE - 1) begin
                            rd_n <= 1'b0;
                            acc_cnt <= acc_cnt + 1'b1;
                        end else if (acc_cnt == EEPROM_ADDR_SETUP + EEPROM_HALF_CYCLE - 1) begin
                            rd_n <= 1'b1;   // rising edge
                            acc_cnt <= acc_cnt + 1'b1;
                        end else begin
                            // Sample one cycle after the edge.
                            eeprom_dout <= cart_tran_bank3[0];
                            acc_cnt <= 8'd0;
                            state   <= S_DONE;
                        end
                    end else begin
                        // Write bit: WR# low pulse (D0 held through the edge)
                        if (acc_cnt < EEPROM_ADDR_SETUP + EEPROM_HALF_CYCLE - 1) begin
                            wr_n <= 1'b0;
                            acc_cnt <= acc_cnt + 1'b1;
                        end else begin
                            wr_n    <= 1'b1;
                            acc_cnt <= 8'd0;
                            state   <= S_DONE;
                        end
                    end
                end

                // ---- EEPROM command-latch pulse ----
                // After the write (command) burst ends and the read burst
                // begins, the real cart needs /CS to rise once so the chip
                // latches the command. Keep A23 high, hold /CS high for a few
                // cycles, then let S_EEPROM pull it low again for the read
                // burst (S_EEPROM keeps /CS low when eeprom_sess is active).
                S_EEPROM_RESET: begin
                    out_bank1     <= 8'h80;      // A23 stays HIGH
                    out_bank1_dir <= 1'b1;
                    out_bank2_dir <= 1'b0;
                    out_bank3_dir <= 1'b0;
                    cs_n          <= 1'b1;       // /CS high pulse
                    rd_n          <= 1'b1;
                    wr_n          <= 1'b1;
                    cs2_n         <= 1'b1;
                    if (acc_cnt < 16) begin
                        acc_cnt <= acc_cnt + 1'b1;
                    end else begin
                        acc_cnt <= 8'd0;
                        state   <= S_EEPROM;     // begin the read burst
                    end
                end

                // ---- GPIO: 16-bit R/W at 0x080000C4..0x080000C8 ----
                S_GPIO_A: begin
                    // Halfword address of 0x080000C4 is 0x04000062; the cart
                    // bus only carries A[23:0], so the low 24 bits are
                    // 0x000062 => A[23:16] = 0x00. Driving A18 high here put
                    // the address outside the ROM-chip GPIO decode window and
                    // the GPIO registers never responded.
                    out_bank1     <= 8'h00;      // A[23:16] of halfword address
                    out_bank2     <= gpio_abs_addr[15:8];
                    out_bank3     <= gpio_abs_addr[7:0];
                    out_bank1_dir <= 1'b1;
                    out_bank2_dir <= 1'b1;
                    out_bank3_dir <= 1'b1;
                    gpio_diag[0]  <= 1'b1;   // request entered S_GPIO_A
                    if (gpio_rnw_r) gpio_diag[7] <= 1'b1;  // read request reached the controller
                    cs_n          <= 1'b1;      // address setup, CS# high
                    rd_n          <= 1'b1;
                    wr_n          <= 1'b1;
                    if (acc_cnt == ADDR_SETUP - 1) begin
                        cs_n <= 1'b0;           // CS# falling edge latches addr
                        gpio_diag[1] <= 1'b1;   // CS1# went low
                        state <= gpio_rnw_r ? S_GPIO_R : S_GPIO_W;
                        acc_cnt <= 8'd0;
                    end else begin
                        acc_cnt <= acc_cnt + 1'b1;
                    end
                end

                S_GPIO_R: begin
                    // CS# has already fallen (S_GPIO_A latched the address).
                    // Hold the address on AD[15:0] for the latch hold time
                    // before releasing it to data, exactly like S_ROM_DATA.
                    if (acc_cnt < ADDR_SETUP) begin
                        rd_n <= 1'b1;
                        acc_cnt <= acc_cnt + 1'b1;
                    end else if (acc_cnt == ADDR_SETUP) begin
                        // Release AD bus (GPIO data comes from cart on AD[3:0])
                        // and start the read strobe.
                        out_bank2_dir <= 1'b0;
                        out_bank3_dir <= 1'b0;
                        rd_n <= 1'b0;
                        acc_cnt <= acc_cnt + 1'b1;
                    end else if (acc_cnt < ADDR_SETUP + SAVE_WAIT - 1) begin
                        rd_n <= 1'b0;
                        acc_cnt <= acc_cnt + 1'b1;
                    end else begin
                        // Sample while RD# is still low: like the ROM path,
                        // the ROM-chip GPIO block drives AD[3:0] during the
                        // RD# low phase and tri-states after RD# rises.
                        // Sampling after the rising edge reads a stale bus.
                        gpio_dout <= cart_tran_bank3[3:0];
                        gpio_diag[3] <= 1'b1;   // read sampled
                        rd_n <= 1'b1;
                        acc_cnt <= 8'd0;
                        state   <= S_GPIO_DONE;
                    end
                end

                S_GPIO_W: begin
                    // Host-like write timing (see GPIO_* parameters): CS# has
                    // already fallen and latched the address; keep the
                    // address driven for a short hold, switch AD to the write
                    // data with a short setup, then pulse WR# low. The total
                    // CS#-low window stays close to a real GBA access so the
                    // ROM-chip GPIO state machine sees a valid write cycle.
                    if (acc_cnt < gpio_wr_addr_hold) begin
                        // Address hold phase, WR#/RD# high.
                        wr_n <= 1'b1;
                        rd_n <= 1'b1;
                        acc_cnt <= acc_cnt + 1'b1;
                    end else if (acc_cnt < gpio_wr_addr_hold + gpio_wr_data_setup) begin
                        // Drive the write data first and hold WR# high during
                        // a setup phase, so the GPIO registers sample stable
                        // data when WR# falls.
                        out_bank2     <= 8'h00;  // AD[15:8] = data high byte
                        out_bank3     <= {4'b0, gpio_din_r};
                        out_bank3_dir <= 1'b1;
                        gpio_diag[6]  <= 1'b1;   // write data driven
                        wr_n    <= 1'b1;
                        acc_cnt <= acc_cnt + 1'b1;
                    end else if (acc_cnt < gpio_wr_addr_hold + gpio_wr_data_setup + gpio_wr_low - 1) begin
                        rd_n <= 1'b1;      // RD# stays high during a write
                        if (gpio_wr_data_setup == 8'd0) begin
                            // Mode 3: drive the data on the same cycle WR#
                            // falls, so the GPIO registers sample the bus at
                            // the WR# edge with zero data setup.
                            out_bank2     <= 8'h00;
                            out_bank3     <= {4'b0, gpio_din_r};
                            gpio_diag[6]  <= 1'b1;
                        end
                        wr_n <= 1'b0;      // WR# low pulse
                        gpio_diag[2] <= 1'b1;   // WR# low issued
                        acc_cnt <= acc_cnt + 1'b1;
                    end else begin
                        wr_n    <= 1'b1;
                        acc_cnt <= 8'd0;
                        state   <= S_GPIO_DONE;
                    end
                end

                S_GPIO_DONE: begin
                    rd_n  <= 1'b1;
                    wr_n  <= 1'b1;
                    if (acc_cnt < GPIO_DONE_HOLD) begin
                        // CS# stays low (write recovery) with data driven.
                        acc_cnt <= acc_cnt + 1'b1;
                    end else if (acc_cnt == GPIO_DONE_HOLD) begin
                        // Raise CS# while data is STILL driven: the GPIO
                        // registers may latch on the CS# rising edge and must
                        // see valid data there (zero hold time = dropped
                        // write, the symptom seen on real carts).
                        cs_n          <= 1'b1;
                        out_bank1_dir <= 1'b0;
                        acc_cnt       <= acc_cnt + 1'b1;
                    end else if (acc_cnt < GPIO_DONE_HOLD * 2) begin
                        // CS# is high, keep data driven for the hold time.
                        acc_cnt <= acc_cnt + 1'b1;
                    end else begin
                        out_bank2_dir <= 1'b0;
                        out_bank3_dir <= 1'b0;
                        gpio_done     <= 1'b1;
                        state         <= S_GPIO_RECOVER;
                        acc_cnt       <= 8'd0;
                    end
                end

                S_GPIO_RECOVER: begin
                    // Keep the cart bus fully idle (CS#/RD#/WR# high, AD
                    // released) for GPIO_RECOVER cycles after every GPIO
                    // access. The ROM-chip GPIO registers need this settle
                    // time before the next GPIO access: without it, reads
                    // return the previous write value and RTC bit-banging
                    // never sees a coherent command. Other accesses (SD ROM
                    // fetch, SDRAM) do not pass through this controller, so
                    // CPU instruction fetch is not stalled by this wait.
                    rd_n  <= 1'b1;
                    wr_n  <= 1'b1;
                    cs_n  <= 1'b1;
                    if (acc_cnt < gpio_recover_wait - 1) begin
                        acc_cnt <= acc_cnt + 1'b1;
                    end else begin
                        acc_cnt <= 8'd0;
                        state   <= S_IDLE;
                    end
                end

                S_DONE: begin
                    rd_n  <= 1'b1;
                    wr_n  <= 1'b1;
                    if (acc_cnt < RELEASE_DELAY - 1) begin
                        // Phase 1 (write recovery): RD#/WR# are already high,
                        // the chip-selects stay low, and the AD bus stays
                        // driven. Real SRAM samples data on the WR# rising
                        // edge, Flash needs WE#-high-while-CE#-low recovery
                        // time, and the ROM-chip GPIO block needs CS#-low
                        // time to process the register write.
                        // CS1# keeps its previous value (low for GPIO/EEPROM
                        // write recovery, high for SRAM/Flash so the ROM chip
                        // is never selected); CS2# (pin30) likewise via the
                        // pin30 mux below.
                        acc_cnt <= acc_cnt + 1'b1;
                    end else if (acc_cnt == RELEASE_DELAY - 1) begin
                        // Phase 2: raise CS# while data is STILL driven.
                        // Chips that latch on the CS# rising edge (the
                        // ROM-chip GPIO registers in real carts) must see
                        // valid data at this edge; releasing the bus in the
                        // same cycle as CS# would give zero hold time and
                        // the GPIO register write would be dropped.
                        if (eeprom_sess && eeprom_dma_r) begin
                            // Keep /CS LOW and A23 HIGH across consecutive
                            // EEPROM bit accesses (GBATEK requirement for DMA3).
                            cs_n          <= 1'b0;
                            out_bank1     <= 8'h80;
                            out_bank1_dir <= 1'b1;
                        end else begin
                            // Standalone access (or DMA burst finished):
                            // release /CS. For write-complete polling this is
                            // what lets the cart chip update its ready bit.
                            cs_n          <= 1'b1;
                            out_bank1_dir <= 1'b0;
                            eeprom_sess   <= 1'b0;
                        end
                        cs2_n         <= 1'b1;   // release CS2# one cycle later
                        acc_cnt       <= acc_cnt + 1'b1;
                    end else if (acc_cnt < RELEASE_DELAY * 2 - 1) begin
                        // Phase 3: CS# is already high, keep the AD bus
                        // driven for RELEASE_DELAY-1 more cycles so the
                        // GPIO/ROM chip gets a real data hold time after the
                        // CS# rising edge.
                        acc_cnt <= acc_cnt + 1'b1;
                    end else begin
                        // Phase 4: release the data bus and complete.
                        out_bank2_dir <= 1'b0;
                        out_bank3_dir <= 1'b0;
                        save_done     <= 1'b1;
                        eeprom_done   <= 1'b1;
                        gpio_done     <= 1'b1;
                        state         <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------
    // Pin drivers
    // ------------------------------------------------------------------
    assign cart_tran_bank1     = out_bank1_dir ? out_bank1 : 8'hzz;
    assign cart_tran_bank1_dir = out_bank1_dir;
    assign cart_tran_bank2     = out_bank2_dir ? out_bank2 : 8'hzz;
    assign cart_tran_bank2_dir = out_bank2_dir;
    assign cart_tran_bank3     = out_bank3_dir ? out_bank3 : 8'hzz;
    assign cart_tran_bank3_dir = out_bank3_dir;

    // bank0 bit layout: [7]=PHI# [6]=WR# [5]=RD# [4]=CS1#
    // PHI follows WAITCNT bit12..11 (disabled/idle-high at reset, GBA
    // default). Only add-on chips that take a clock need it (tilt sensor
    // ADC, camera); GPIO register R/W itself works with PHI disabled.
    // Explicit [7:4] mapping, matching core_top/apf_top - no implicit
    // slicing/alignment involved.
    // PHI output: driven only while WAITCNT enables it (real GBA tri-states
    // the PHI terminal when disabled). Driving the pin high while "disabled"
    // fights whatever the Pocket slot circuitry / cartridge does with it and
    // can keep the ROM-chip GPIO block from seeing a valid PHI state.
    assign cart_tran_bank0[7]  = phi_enable ? phi : 1'bz;
    assign cart_tran_bank0[6]  = wr_n;
    assign cart_tran_bank0[5]  = rd_n;
    assign cart_tran_bank0[4]  = cs_n;
    assign cart_tran_bank0_dir = 1'b1;

    // pin30: CS2#/RES# — CS2# active during SRAM/Flash accesses and for one
    // extra cycle in S_DONE (so WR#/RD# rise while CS2# is still low, as real
    // SRAM chips require); during EEPROM transfers pin30 stays at RES#
    // (EEPROM /CS is ROMCS, Pin 5).
    assign cart_tran_pin30        = ((state == S_SRAM) ||
                                     ((state == S_DONE) && (acc_cnt < RELEASE_DELAY - 1))) ? cs2_n : res_n;
    assign cart_tran_pin30_dir    = 1'b1;
    assign cart_pin30_pwroff_reset = 1'b0;

    assign cart_tran_pin31     = 1'bz;
    assign cart_tran_pin31_dir = 1'b0;

endmodule

`default_nettype wire
