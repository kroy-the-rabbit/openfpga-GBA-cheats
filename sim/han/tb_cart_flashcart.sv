// SPDX-License-Identifier: GPL-3.0-or-later
// Flash-cart register traffic through cart_bus_arbiter and the real
// gba_cart_controller, against pin-level models of an EZ-Flash Omega
// Definitive Edition and an EverDrive GBA.
//
// Both carts are driven through ROM space. The sequences below are the ones
// their own software issues, from ez-flash/omega-de-kernel Ezcard_OP.c and the
// EverDrive X5 driver in afska/gba-flashcartio:
//
//   Omega DE  unlock D200@09FE0000 1500@08000000 D200@08020000 1500@08040000,
//             one register write, lock 1500@09FC0000. The FPGA version is
//             read at 09E00000 with SPI control 1; SD status is polled there
//             with SD control 3 until it stops reading EEE1; sector data is
//             read there with SD control 1. SetRompage moves what ROM shows.
//   EverDrive registers at 09FC0000 + 2*n. ed_init_sd_only writes KEY 0,
//             proves SD_CFG does not take a write while locked, writes KEY
//             A5, proves it does now. SD_DAT at 09FC0012 is a FIFO: each read
//             takes one halfword. ed_sd_dma_rd in krikzz/gba-ed-pub copies a
//             sector with DMA from SD_DAT with the source incrementing; on a
//             GBA that is one CS# fall and 256 RD# pulses, and the register
//             decode follows the latched address, not the advanced one.
//
// Checked: every value the software would read, exactly one RD# pulse per IO
// read and one WR# pulse per IO write, a turnaround before every RD#, no RD#
// during a write, no FIFO read consumed by anything but the software's own
// reads, a DMA copy held as one sequential burst and separate CPU reads never
// joined into one, and that 8-byte ROM line reads still work against the same
// cart after it has been written to.
`timescale 1ns / 1ps
`default_nettype none

module flashcart_model #(parameter EVERDRIVE = 0) (
    inout  wire [7:0] bank2,      // AD[15:8]
    inout  wire [7:0] bank3,      // AD[7:0]
    inout  wire [7:0] bank1,      // A[23:16]
    inout  wire [3:0] bank0,      // [0]=CS1# [1]=RD# [2]=WR# [3]=PHI#
    input  wire       bank2_dir,  // 1 = host drives AD[15:8]
    input  wire       bank3_dir,  // 1 = host drives AD[7:0]
    output integer    rd_pulses,
    output integer    wr_pulses,
    output integer    fifo_pops,
    output integer    cs_falls
);
    wire cs_n = bank0[0];
    wire rd_n = bank0[1];
    wire wr_n = bank0[2];

    // Omega DE state
    reg  [2:0]  unlock_seq = 0;
    reg         unlocked   = 0;
    reg  [15:0] sd_ctl = 0, spi_ctl = 0, rompage = 16'h8000;
    integer     busy_reads = 0;
    // EverDrive state
    reg         ed_unlocked = 0;
    reg  [15:0] ed_sd_cfg = 16'h0000;
    integer     fifo_head = 0;

    reg  [23:0] addr, latched;
    initial begin
        rd_pulses = 0; wr_pulses = 0; fifo_pops = 0; cs_falls = 0;
    end

    function [15:0] rom_word(input [23:0] a, input [15:0] page);
        rom_word = (a[15:0] * 16'h9E37) ^ {8'h00, a[23:16]} ^ page;
    endfunction

    // What the cart drives for a read at the latched address.
    function [15:0] read_value(input [23:0] a);
        begin
            read_value = rom_word(a, EVERDRIVE ? 16'h0000 : rompage);
            if (!EVERDRIVE && a[23:16] == 8'hF0) begin
                if (spi_ctl == 16'd1 && a[15:0] == 0) read_value = 16'hB007;       // LX16, firmware 7
                else if (sd_ctl == 16'd3)             read_value = busy_reads ? 16'hEEE1 : 16'h0000;
                else if (sd_ctl == 16'd1)             read_value = 16'h5D00 ^ a[15:0];
            end
            if (EVERDRIVE && ed_unlocked) begin
                if (latched == 24'hFE000A) read_value = ed_sd_cfg;
                if (latched == 24'hFE0009) read_value = 16'hF000 + fifo_head;
            end
        end
    endfunction

    always @(negedge cs_n) begin
        #2 addr = {bank1, bank2, bank3};
        latched = addr;
        cs_falls = cs_falls + 1;
    end

    // The Pocket's translators need a turnaround: AD released well before
    // RD# falls. A strobe on the clock AD was released is ROM profile Fast,
    // which failed on a real cart.
    realtime released = 0;
    always @(negedge bank2_dir or negedge bank3_dir) released = $realtime;
    reg [15:0] dout;
    always @(negedge rd_n) begin
        rd_pulses = rd_pulses + 1;
        if (bank2_dir !== 1'b0 || bank3_dir !== 1'b0)
            $fatal(1, "FAIL RD# fell while the host still drove AD");
        if ($realtime - released < 35.0)
            $fatal(1, "FAIL RD# fell %0.1f ns after AD was released, no turnaround", $realtime - released);
        dout = read_value(addr);
    end
    always @(posedge rd_n) if (cs_n === 1'b0) begin
        if (!EVERDRIVE && sd_ctl == 16'd3 && addr[23:16] == 8'hF0 && busy_reads) busy_reads = busy_reads - 1;
        if (EVERDRIVE && ed_unlocked && latched == 24'hFE0009) begin
            fifo_head = fifo_head + 1; fifo_pops = fifo_pops + 1;
        end
        addr[15:0] = addr[15:0] + 16'd1;
    end

    always @(posedge wr_n) if (cs_n === 1'b0) begin : write
        reg [15:0] d;
        d = {bank2, bank3};
        wr_pulses = wr_pulses + 1;
        if (!EVERDRIVE) begin
            if (unlocked) begin
                case (addr)
                    24'hFE0000: if (d == 16'h1500) unlocked = 0;
                    24'hA00000: begin sd_ctl = d; if (d == 16'd3) busy_reads = 5; end
                    24'hB30000: spi_ctl = d;
                    24'hC40000: rompage = d;
                    default: ;
                endcase
            end else begin
                case (unlock_seq)
                    0: unlock_seq = (addr == 24'hFF0000 && d == 16'hD200) ? 1 : 0;
                    1: unlock_seq = (addr == 24'h000000 && d == 16'h1500) ? 2 : 0;
                    2: unlock_seq = (addr == 24'h010000 && d == 16'hD200) ? 3 : 0;
                    3: begin unlock_seq = 0; unlocked = (addr == 24'h020000 && d == 16'h1500); end
                    default: unlock_seq = 0;
                endcase
            end
        end else begin
            if (addr == 24'hFE005A) ed_unlocked = (d == 16'h00A5);
            else if (ed_unlocked && addr == 24'hFE000A) ed_sd_cfg = d;
        end
    end

    wire drive = (cs_n === 1'b0) && (rd_n === 1'b0);
    assign bank2 = drive ? dout[15:8] : 8'hzz;
    assign bank3 = drive ? dout[7:0]  : 8'hzz;
    assign bank1 = 8'hzz;
endmodule


module tb_cart_flashcart;
    parameter EVERDRIVE = 0;
    reg clk = 0, reset_n = 0;
    always #5 clk = ~clk;

    // Host side: the requests gba_memorymux issues.
    reg         rom_req = 0;
    reg  [24:0] rom_addr = 0;
    wire        rom_done;
    reg         io_req = 0, io_rnw = 1, io_hold = 0;
    reg  [23:0] io_addr = 0;
    reg  [15:0] io_din = 0;
    wire        io_done;

    wire        c_rom_req, c_io_req, c_io_rnw, c_io_done, c_rom_done;
    wire [24:0] c_rom_addr;
    wire [23:0] c_io_addr;
    wire [15:0] c_io_din, io_dout;
    wire        c_save_req, c_save_rnw, c_ee_req, c_ee_rnw, c_ee_din, c_ee_dma;
    wire [16:0] c_save_addr;
    wire [7:0]  c_save_din;

    cart_bus_arbiter arb (
        .clk(clk), .reset_n(reset_n),
        .probe_req(1'b0), .probe_addr(25'd0), .probe_done(),
        .rom_req(rom_req), .rom_addr(rom_addr), .rom_done(rom_done),
        .save_req(1'b0), .save_addr(17'd0), .save_rnw(1'b1), .save_din(8'd0), .save_done(),
        .ee_req(1'b0), .ee_rnw(1'b1), .ee_din(1'b0), .ee_dma(1'b0), .ee_done(),
        .io_req(io_req), .io_rnw(io_rnw), .io_addr(io_addr), .io_din(io_din), .io_done(io_done),
        .ctl_rom_req(c_rom_req), .ctl_rom_addr(c_rom_addr), .ctl_rom_done(c_rom_done),
        .ctl_save_req(c_save_req), .ctl_save_addr(c_save_addr), .ctl_save_rnw(c_save_rnw),
        .ctl_save_din(c_save_din), .ctl_save_done(1'b0),
        .ctl_ee_req(c_ee_req), .ctl_ee_rnw(c_ee_rnw), .ctl_ee_din(c_ee_din), .ctl_ee_dma(c_ee_dma),
        .ctl_ee_done(1'b0),
        .ctl_io_req(c_io_req), .ctl_io_rnw(c_io_rnw), .ctl_io_addr(c_io_addr),
        .ctl_io_din(c_io_din), .ctl_io_done(c_io_done), .busy()
    );

    wire [7:0] b1, b2, b3;
    wire [3:0] b0;
    wire       b1d, b2d, b3d, b0d, p30, p30d, p30r, p31, p31d;
    wire [31:0] rd_data, rd_data2;

    gba_cart_controller #(.RESET_LEN(8)) ctl (
        .clk(clk), .reset_n(reset_n), .phi_sel(2'd0), .rom_profile(3'd1),
        .cart_tran_bank2(b2), .cart_tran_bank2_dir(b2d),
        .cart_tran_bank3(b3), .cart_tran_bank3_dir(b3d),
        .cart_tran_bank1(b1), .cart_tran_bank1_dir(b1d),
        .cart_tran_bank0(b0), .cart_tran_bank0_dir(b0d),
        .cart_tran_pin30(p30), .cart_tran_pin30_dir(p30d),
        .cart_pin30_pwroff_reset(p30r),
        .cart_tran_pin31(p31), .cart_tran_pin31_dir(p31d),
        .rd_req(c_rom_req), .rd_addr(c_rom_addr),
        .rd_data(rd_data), .rd_data_second(rd_data2), .rd_ready(c_rom_done),
        .save_req(1'b0), .save_addr(17'd0), .save_rnw(1'b1), .save_din(8'd0),
        .save_dout(), .save_done(),
        .eeprom_req(1'b0), .eeprom_rnw(1'b1), .eeprom_din(1'b0), .eeprom_dma(1'b0),
        .eeprom_dout(), .eeprom_done(),
        .io_req(c_io_req), .io_rnw(c_io_rnw), .io_addr(c_io_addr), .io_din(c_io_din),
        .io_dout(io_dout), .io_done(c_io_done), .io_hold(io_hold),
        .gpio_req(1'b0), .gpio_rnw(1'b1), .gpio_addr(2'd0), .gpio_din(4'd0),
        .gpio_dout(), .gpio_done(),
        .gpio_timing_mode(3'd0), .gpio_recover_set(14'd0),
        .gpio_diag(), .cart_present(), .err_count()
    );

    integer rd_pulses, wr_pulses, fifo_pops, cs_falls;
    flashcart_model #(.EVERDRIVE(EVERDRIVE)) cart (
        .bank2(b2), .bank3(b3), .bank1(b1), .bank0(b0),
        .bank2_dir(b2d), .bank3_dir(b3d),
        .rd_pulses(rd_pulses), .wr_pulses(wr_pulses), .fifo_pops(fifo_pops),
        .cs_falls(cs_falls)
    );

    // The software's own view: byte addresses in 08000000..09FFFFFF.
    function [23:0] hw(input [31:0] byte_addr);
        hw = (byte_addr - 32'h08000000) >> 1;
    endfunction

    task automatic wr(input [31:0] a, input [15:0] d);
        integer rd0, wr0;
        begin
            rd0 = rd_pulses; wr0 = wr_pulses;
            @(negedge clk); io_req = 1; io_rnw = 0; io_addr = hw(a); io_din = d;
            @(negedge clk); io_req = 0;
            wait (io_done); @(negedge clk);
            if (wr_pulses != wr0 + 1 || rd_pulses != rd0)
                $fatal(1, "FAIL write %h=%h: %0d WR# and %0d RD# pulses", a, d, wr_pulses - wr0, rd_pulses - rd0);
        end
    endtask

    task automatic rd(input [31:0] a, output [15:0] q);
        integer rd0, wr0;
        begin
            rd0 = rd_pulses; wr0 = wr_pulses;
            @(negedge clk); io_req = 1; io_rnw = 1; io_addr = hw(a);
            @(negedge clk); io_req = 0;
            wait (io_done); @(negedge clk);
            q = io_dout;
            if (rd_pulses != rd0 + 1 || wr_pulses != wr0)
                $fatal(1, "FAIL read %h: %0d RD# and %0d WR# pulses", a, rd_pulses - rd0, wr_pulses - wr0);
        end
    endtask

    task automatic omega_reg(input [31:0] a, input [15:0] d);
        begin
            wr(32'h09FE0000, 16'hD200); wr(32'h08000000, 16'h1500);
            wr(32'h08020000, 16'hD200); wr(32'h08040000, 16'h1500);
            wr(a, d);
            wr(32'h09FC0000, 16'h1500);
        end
    endtask

    task automatic rom_line(input [31:0] a, output [31:0] first);
        begin
            @(negedge clk); rom_req = 1; rom_addr = (a - 32'h08000000) >> 2;
            @(negedge clk); rom_req = 0;
            wait (rom_done); @(negedge clk);
            first = rd_data;
        end
    endtask

    function [15:0] rom_expect(input [23:0] a, input [15:0] page);
        rom_expect = (a[15:0] * 16'h9E37) ^ {8'h00, a[23:16]} ^ page;
    endfunction

    reg [15:0] q, prior;
    reg [31:0] line;
    integer n, polls, falls;
    initial begin
        repeat (4) @(negedge clk); reset_n = 1;
        repeat (20) @(negedge clk);
        if (!EVERDRIVE) begin
            // Check_FW_update: a firmware 7 LX16 card must read as B007, or
            // the kernel offers to reflash the card.
            omega_reg(32'h09660000, 16'd1);
            rd(32'h09E00000, q);
            if (q !== 16'hB007) $fatal(1, "FAIL Omega FPGA version read %h, expected B007", q);
            omega_reg(32'h09660000, 16'd0);
            // Read_SD_sectors: status polls, then 256 halfwords of sector.
            omega_reg(32'h09400000, 16'd1);
            omega_reg(32'h09400000, 16'd3);
            polls = 0;
            do begin rd(32'h09E00000, q); polls = polls + 1; end while (q == 16'hEEE1 && polls < 20);
            if (polls != 6) $fatal(1, "FAIL Omega SD status took %0d polls, expected 6", polls);
            omega_reg(32'h09400000, 16'd1);
            // dmaCopy(0x9E00000, buffer, 512): one sequential burst.
            falls = cs_falls; io_hold = 1;
            for (n = 0; n < 256; n = n + 1) begin
                rd(32'h09E00000 + 2*n, q);
                if (q !== (16'h5D00 ^ n)) $fatal(1, "FAIL Omega sector halfword %0d read %h", n, q);
            end
            io_hold = 0;
            if (cs_falls != falls + 1) $fatal(1, "FAIL Omega sector copy took %0d CS# falls, expected 1", cs_falls - falls);
            omega_reg(32'h09400000, 16'd0);
            // SetRompage: an 8-byte ROM line shows the new page afterwards.
            rom_line(32'h08000100, line);
            if (line[15:0] !== rom_expect(hw(32'h08000100), 16'h8000))
                $fatal(1, "FAIL Omega bootloader page line %h", line);
            omega_reg(32'h09880000, 16'h0200);
            rom_line(32'h08000100, line);
            if (line[15:0] !== rom_expect(hw(32'h08000100), 16'h0200) ||
                line[31:16] !== rom_expect(hw(32'h08000102), 16'h0200))
                $fatal(1, "FAIL Omega game page line %h", line);
            $display("PASS Omega DE: unlock/lock, firmware B007, 6 SD status polls, 256 sector halfwords, ROM page switch, one strobe per access");
        end else begin
            // ed_init_sd_only, as written.
            wr(32'h09FC00B4, 16'h0000);
            rd(32'h09FC0014, prior);
            wr(32'h09FC0014, 16'h0000);
            rd(32'h09FC0014, q);
            if (q !== prior) $fatal(1, "FAIL EverDrive SD_CFG took a write while locked");
            wr(32'h09FC00B4, 16'h00A5);
            wr(32'h09FC0014, 16'h0000);
            rd(32'h09FC0014, q);
            if (q === prior) $fatal(1, "FAIL EverDrive SD_CFG did not take a write once unlocked");
            // SD_DAT pops once per CPU read, never more.
            for (n = 0; n < 8; n = n + 1) begin
                rd(32'h09FC0012, q);
                if (q !== 16'hF000 + n) $fatal(1, "FAIL EverDrive SD_DAT read %0d gave %h", n, q);
            end
            if (fifo_pops != 8) $fatal(1, "FAIL EverDrive SD_DAT popped %0d times for 8 reads", fifo_pops);
            // CPU reads of neighbouring registers are separate accesses:
            // SD_CFG after SD_DAT must not become a sequential SD_DAT read.
            rd(32'h09FC0012, q);
            rd(32'h09FC0014, q);
            if (q !== 16'h0000 || fifo_pops != 9) $fatal(1, "FAIL EverDrive CPU reads were joined: SD_CFG %h, %0d pops", q, fifo_pops);
            // ed_sd_dma_rd: DMA from SD_DAT, source incrementing, 256 words.
            falls = cs_falls; io_hold = 1;
            for (n = 0; n < 256; n = n + 1) begin
                rd(32'h09FC0012 + 2*n, q);
                if (q !== 16'hF009 + n) $fatal(1, "FAIL EverDrive DMA sector word %0d gave %h", n, q);
            end
            if (cs_falls != falls + 1) $fatal(1, "FAIL EverDrive DMA copy took %0d CS# falls, expected 1", cs_falls - falls);
            if (fifo_pops != 265) $fatal(1, "FAIL EverDrive DMA copy popped %0d, expected 265", fifo_pops);
            // A ROM read ends the burst even while the hold is still up.
            rom_line(32'h08000100, line);
            if (line[15:0] !== rom_expect(hw(32'h08000100), 16'h0000))
                $fatal(1, "FAIL EverDrive ROM line after register traffic %h", line);
            rd(32'h09FC0212, q);
            if (q !== rom_expect(hw(32'h09FC0212), 16'h0000) || cs_falls != falls + 3)
                $fatal(1, "FAIL EverDrive read after a ROM line was not re-latched: %h", q);
            io_hold = 0;
            if (fifo_pops != 265) $fatal(1, "FAIL ROM line read disturbed the SD_DAT FIFO");
            $display("PASS EverDrive: locked write refused, KEY A5 unlock, SD_CFG readback, single SD_DAT pops, CPU reads kept apart, 256-word DMA burst on one CS#, ROM line after, one strobe per access");
        end
        $finish;
    end
    initial begin #50000000; $fatal(1, "FAIL flash cart watchdog"); end
endmodule

`default_nettype wire
