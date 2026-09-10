// tb_gba_cart_rom_burst.sv
//
// Covers the ROM read burst path in src/fpga/han/gba_cart_controller.sv.
//
// Wokann's sim/han/tb_gba_cart_controller.sv, vendored beside this file,
// cannot test a burst. Its cart_rom_model derives ROM data purely from the
// address latched on the CS# falling edge and has no internal counter, so a
// burst reads the same halfword four times and their ROM check fails on a
// model limitation rather than a controller defect. That bench stays as the
// whole-controller regression (SRAM, GPIO, EEPROM) and is run with
// ROM_BURST=0.
//
// This bench adds a cart model that does what a real cart does:
//   - latch A[23:0] on the CS# falling edge,
//   - drive AD[15:0] only while CS# and RD# are both low, high-Z otherwise,
//   - advance the low 16 bits of the latched address on every RD# rising
//     edge (GBATEK: the sequential counter wraps every 128K bytes, which is
//     why the GBA forces a non-sequential access at each 128K block start).
//
// Two controllers run against two identical copies of it:
//   dut_ref    ROM_BURST=0, the original per-word path (full address
//              re-driven and CS# re-asserted for every halfword)
//   dut_burst  ROM_BURST=1, the burst path
//
// Both see the same requests. Checked per request:
//   - dut_burst returns the same rd_data / rd_data_second as dut_ref,
//   - both agree with expect_word(), written independently of the model's
//     rom_word() so a lane or byte-order mistake in either shows up rather
//     than cancelling out,
//   - no returned bit is x or z, i.e. every halfword was sampled inside a
//     window where the model was actually driving (CS# low and RD# low),
//   - the pin waveform: how many times CS# fell, what address was latched on
//     each fall, how many RD# pulses were issued, and how many times the
//     cart's counter advanced,
//   - the host never re-drives AD while CS# is low, never strobes RD# with
//     CS# high, and never strobes RD# while it is still driving AD.
//
// Default sequential pulse widths are checked separately: 4 clocks high and
// 8 clocks low, which is a real GBA's WAITCNT 4317h sequential access, the
// setting games actually use. The immediate data model does not prove
// electrical margin.
// Whole-request cycle counts for both paths are also reported.

`timescale 1ns / 1ps

module cart_seq_rom_model #(parameter HEADER = 0) (
    inout  wire [7:0] bank2,      // AD[15:8]
    inout  wire [7:0] bank3,      // AD[7:0]
    inout  wire [7:0] bank1,      // A[23:16]
    inout  wire [3:0] bank0,      // [0]=CS1# [1]=RD# [2]=WR# [3]=PHI#
    input  wire       bank2_dir,  // 1 = host drives AD[15:8]
    input  wire       bank3_dir,  // 1 = host drives AD[7:0]

    output reg [31:0] cs_falls,
    output reg [31:0] rd_falls,
    output reg [31:0] incs,
    output reg        err_redrive,
    output reg        err_rd_no_cs,
    output reg        err_rd_while_out
);
    wire cs_n = bank0[0];
    wire rd_n = bank0[1];

    reg [31:0] header[0:47];
    initial if (HEADER) $readmemh("sim/fixtures/bmxe-header.hex", header);
    // Cart contents. Multiplying the halfword address by an odd constant is a
    // bijection on 16 bits, so any wrong address gives a different halfword.
    function [15:0] rom_word(input [23:0] a);
        reg [15:0] m;
        begin
            m = a[15:0] * 16'h9E37;
            rom_word = m ^ {8'h00, a[23:16]} ^ 16'hC0DE;
            if (HEADER && a < 96) rom_word = a[0] ? header[a>>1][31:16] : header[a>>1][15:0];
        end
    endfunction

    reg [23:0] addr;
    reg [23:0] latch_log [0:63];   // address latched on each CS# fall

    integer i;
    initial begin
        cs_falls         = 0;
        rd_falls         = 0;
        incs             = 0;
        err_redrive      = 0;
        err_rd_no_cs     = 0;
        err_rd_while_out = 0;
        addr             = 24'd0;
        for (i = 0; i < 64; i = i + 1) latch_log[i] = 24'hxxxxxx;
    end

    // Address latch. The delay lets the host's registered bank outputs settle;
    // they change on the same clock edge that drops CS#.
    always @(negedge cs_n) begin
        #2;
        addr = {bank1, bank2, bank3};
        if (cs_falls < 64) latch_log[cs_falls] = addr;
        cs_falls = cs_falls + 1;
    end

    always @(negedge rd_n) begin
        rd_falls = rd_falls + 1;
        if (cs_n !== 1'b0) err_rd_no_cs = 1;
        if (bank2_dir !== 1'b0 || bank3_dir !== 1'b0) err_rd_while_out = 1;
    end

    // The cart's own sequential counter: low 16 bits only, so it wraps at each
    // 128K byte block exactly as a real cart does.
    always @(posedge rd_n) begin
        if (cs_n === 1'b0) begin
            addr[15:0] = addr[15:0] + 16'd1;
            incs = incs + 1;
        end
    end

    // The host taking AD back while CS# is still low is an address re-drive,
    // which is the thing the burst exists to remove.
    always @(posedge bank2_dir or posedge bank3_dir) begin
        if (cs_n === 1'b0) err_redrive = 1;
    end

    wire [15:0] dout = rom_word(addr);
    wire        drive = (cs_n === 1'b0) && (rd_n === 1'b0);
    assign bank2 = drive ? dout[15:8] : 8'hzz;
    assign bank3 = drive ? dout[7:0]  : 8'hzz;
    assign bank1 = 8'hzz;
endmodule


module tb_gba_cart_rom_burst;
    reg clk = 0;
    reg reset_n = 0;
    always #5 clk = ~clk;      // 100 MHz

    reg         rd_req  = 0;
    reg  [24:0] rd_addr = 0;

    // ---- reference: per-word path ----
    wire [7:0] r_b2, r_b3, r_b1;
    wire       r_b2d, r_b3d, r_b1d;
    wire [3:0] r_b0;
    wire       r_b0d, r_p30, r_p30d, r_p30r, r_p31, r_p31d;
    wire [31:0] r_data, r_data2;
    wire        r_ready;
    wire [7:0]  r_sdout, r_diag, r_err;
    wire        r_sdone, r_edout, r_edone, r_gdone, r_present;
    wire [3:0]  r_gdout;

    gba_cart_controller #(.ROM_BURST(0)) dut_ref (
        .rom_profile(2'd0),
        .clk(clk), .reset_n(reset_n), .phi_sel(2'd0),
        .cart_tran_bank2(r_b2), .cart_tran_bank2_dir(r_b2d),
        .cart_tran_bank3(r_b3), .cart_tran_bank3_dir(r_b3d),
        .cart_tran_bank1(r_b1), .cart_tran_bank1_dir(r_b1d),
        .cart_tran_bank0(r_b0), .cart_tran_bank0_dir(r_b0d),
        .cart_tran_pin30(r_p30), .cart_tran_pin30_dir(r_p30d),
        .cart_pin30_pwroff_reset(r_p30r),
        .cart_tran_pin31(r_p31), .cart_tran_pin31_dir(r_p31d),
        .rd_req(rd_req), .rd_addr(rd_addr),
        .rd_data(r_data), .rd_data_second(r_data2), .rd_ready(r_ready),
        .save_req(1'b0), .save_addr(17'd0), .save_rnw(1'b1), .save_din(8'd0),
        .save_dout(r_sdout), .save_done(r_sdone),
        .eeprom_req(1'b0), .eeprom_rnw(1'b1), .eeprom_din(1'b0),
        .eeprom_dma(1'b1), .eeprom_dout(r_edout), .eeprom_done(r_edone),
        .gpio_req(1'b0), .gpio_rnw(1'b1), .gpio_addr(2'd0), .gpio_din(4'd0),
        .gpio_dout(r_gdout), .gpio_done(r_gdone),
        .gpio_timing_mode(3'd0), .gpio_recover_set(14'd0),
        .gpio_diag(r_diag), .cart_present(r_present), .err_count(r_err)
    );

    wire [31:0] r_csf, r_rdf, r_inc;
    wire        r_eredr, r_erdcs, r_erdout;
    cart_seq_rom_model cart_ref (
        .bank2(r_b2), .bank3(r_b3), .bank1(r_b1), .bank0(r_b0),
        .bank2_dir(r_b2d), .bank3_dir(r_b3d),
        .cs_falls(r_csf), .rd_falls(r_rdf), .incs(r_inc),
        .err_redrive(r_eredr), .err_rd_no_cs(r_erdcs),
        .err_rd_while_out(r_erdout)
    );

    // ---- burst path ----
    wire [7:0] b_b2, b_b3, b_b1;
    wire       b_b2d, b_b3d, b_b1d;
    wire [3:0] b_b0;
    wire       b_b0d, b_p30, b_p30d, b_p30r, b_p31, b_p31d;
    wire [31:0] b_data, b_data2;
    wire        b_ready;
    wire [7:0]  b_sdout, b_diag, b_err;
    wire        b_sdone, b_edout, b_edone, b_gdone, b_present;
    wire [3:0]  b_gdout;

    gba_cart_controller #(.ROM_BURST(1)) dut_burst (
        .rom_profile(2'd0),
        .clk(clk), .reset_n(reset_n), .phi_sel(2'd0),
        .cart_tran_bank2(b_b2), .cart_tran_bank2_dir(b_b2d),
        .cart_tran_bank3(b_b3), .cart_tran_bank3_dir(b_b3d),
        .cart_tran_bank1(b_b1), .cart_tran_bank1_dir(b_b1d),
        .cart_tran_bank0(b_b0), .cart_tran_bank0_dir(b_b0d),
        .cart_tran_pin30(b_p30), .cart_tran_pin30_dir(b_p30d),
        .cart_pin30_pwroff_reset(b_p30r),
        .cart_tran_pin31(b_p31), .cart_tran_pin31_dir(b_p31d),
        .rd_req(rd_req), .rd_addr(rd_addr),
        .rd_data(b_data), .rd_data_second(b_data2), .rd_ready(b_ready),
        .save_req(1'b0), .save_addr(17'd0), .save_rnw(1'b1), .save_din(8'd0),
        .save_dout(b_sdout), .save_done(b_sdone),
        .eeprom_req(1'b0), .eeprom_rnw(1'b1), .eeprom_din(1'b0),
        .eeprom_dma(1'b1), .eeprom_dout(b_edout), .eeprom_done(b_edone),
        .gpio_req(1'b0), .gpio_rnw(1'b1), .gpio_addr(2'd0), .gpio_din(4'd0),
        .gpio_dout(b_gdout), .gpio_done(b_gdone),
        .gpio_timing_mode(3'd0), .gpio_recover_set(14'd0),
        .gpio_diag(b_diag), .cart_present(b_present), .err_count(b_err)
    );

    wire [31:0] b_csf, b_rdf, b_inc;
    wire        b_eredr, b_erdcs, b_erdout;
    cart_seq_rom_model cart_bst (
        .bank2(b_b2), .bank3(b_b3), .bank1(b_b1), .bank0(b_b0),
        .bank2_dir(b_b2d), .bank3_dir(b_b3d),
        .cs_falls(b_csf), .rd_falls(b_rdf), .incs(b_inc),
        .err_redrive(b_eredr), .err_rd_no_cs(b_erdcs),
        .err_rd_while_out(b_erdout)
    );

    // ------------------------------------------------------------------
    // Expected cart contents, written independently of the model's
    // rom_word() so that a mistake in one does not cancel the other out.
    // ------------------------------------------------------------------
    function [15:0] expect_word(input [23:0] a);
        reg [31:0] p;
        begin
            p = {16'd0, a[15:0]} * 32'h0000_9E37;
            expect_word = p[15:0] ^ 16'hC0DE ^ {8'h00, a[23:16]};
        end
    endfunction

    integer errors = 0;
    integer cyc_ref, cyc_bst;
    integer tot_ref = 0, tot_bst = 0, nreq = 0;
    integer whole_ref = 0, whole_bst = 0, nwhole = 0;

    // Check actual edges, not parameter arithmetic. A new CS# assertion
    // starts a non-sequential access, including a 128 KiB boundary fallback.
    time seq_rise = 0, seq_fall = 0;
    reg have_seq_rise = 0, low_is_seq = 0;
    integer seq_pulses = 0;
    always @(negedge b_b0[0]) have_seq_rise = 0;
    always @(negedge b_b0[1]) begin
        low_is_seq = reset_n && have_seq_rise;
        seq_fall = $time;
        if (low_is_seq && ($time - seq_rise != 40))
            fail("default sequential RD high is not 4 clocks");
    end
    always @(posedge b_b0[1]) begin
        if (reset_n && low_is_seq) begin
            if ($time - seq_fall != 80)
                fail("default sequential RD low is not 8 clocks");
            seq_pulses = seq_pulses + 1;
        end
        low_is_seq = 0;
        seq_rise = $time;
        have_seq_rise = reset_n && (b_b0[0] === 1'b0);
    end

    task do_read(input [24:0] a);
        begin
            @(posedge clk); #1;
            rd_req  = 1;
            rd_addr = a;
            @(posedge clk); #1;      // both DUTs accept on this edge
            rd_req  = 0;
            cyc_ref = 0;
            cyc_bst = 0;
            fork
                begin
                    while (r_ready !== 1'b1) begin
                        @(posedge clk); #1; cyc_ref = cyc_ref + 1;
                    end
                end
                begin
                    while (b_ready !== 1'b1) begin
                        @(posedge clk); #1; cyc_bst = cyc_bst + 1;
                    end
                end
            join
            tot_ref = tot_ref + cyc_ref;
            tot_bst = tot_bst + cyc_bst;
            nreq    = nreq + 1;
        end
    endtask

    task fail(input [8*48:1] what);
        begin
            $display("FAIL: %0s", what);
            errors = errors + 1;
        end
    endtask

    // One request, fully checked. want_cs is how many CS# falling edges the
    // burst path is expected to need: 1 normally, 2 when the request straddles
    // a 128K block and the burst has to fall back and re-drive.
    task check_read(input [24:0] a, input integer want_cs);
        reg [23:0] base;
        reg [31:0] cs0_r, cs0_b, rd0_r, rd0_b, in0_b, in0_r;
        reg [63:0] want;
        integer k;
        begin
            base  = {a, 1'b0};
            cs0_r = r_csf; cs0_b = b_csf;
            rd0_r = r_rdf; rd0_b = b_rdf;
            in0_b = b_inc; in0_r = r_inc;

            do_read(a);
            if (want_cs == 1) begin
                whole_ref = whole_ref + cyc_ref;
                whole_bst = whole_bst + cyc_bst;
                nwhole    = nwhole + 1;
            end

            want = {expect_word(base + 3), expect_word(base + 2),
                    expect_word(base + 1), expect_word(base + 0)};

            $display("REQ addr=%07h base=%06h ref=%08h_%08h burst=%08h_%08h cyc ref=%0d burst=%0d cs=%0d rd=%0d inc=%0d",
                     a, base, r_data2, r_data, b_data2, b_data,
                     cyc_ref, cyc_bst,
                     b_csf - cs0_b, b_rdf - rd0_b, b_inc - in0_b);

            // 1. burst returns exactly what the per-word path returns
            if (b_data !== r_data || b_data2 !== r_data2) begin
                $display("FAIL: burst/per-word mismatch at %07h: ref %08h_%08h burst %08h_%08h",
                         a, r_data2, r_data, b_data2, b_data);
                errors = errors + 1;
            end
            // 2. and both are the cart's actual contents
            if ({r_data2, r_data} !== want) begin
                $display("FAIL: per-word data at %07h: got %08h_%08h want %016h",
                         a, r_data2, r_data, want);
                errors = errors + 1;
            end
            if ({b_data2, b_data} !== want) begin
                $display("FAIL: burst data at %07h: got %08h_%08h want %016h",
                         a, b_data2, b_data, want);
                errors = errors + 1;
            end
            // 3. nothing sampled outside a window where the cart was driving
            if ((^{b_data2, b_data}) === 1'bx) fail("burst sampled x/z");
            if ((^{r_data2, r_data}) === 1'bx) fail("per-word sampled x/z");

            // 4. waveform: CS# falls, RD# pulses, counter advances
            if ((r_csf - cs0_r) != 4)
                $display("FAIL: per-word CS# falls = %0d, expected 4",
                         r_csf - cs0_r);
            if ((r_csf - cs0_r) != 4) errors = errors + 1;
            if ((b_csf - cs0_b) != want_cs) begin
                $display("FAIL: burst CS# falls = %0d, expected %0d",
                         b_csf - cs0_b, want_cs);
                errors = errors + 1;
            end
            if ((r_rdf - rd0_r) != 4 || (b_rdf - rd0_b) != 4) begin
                $display("FAIL: RD# pulses ref=%0d burst=%0d, expected 4 each",
                         r_rdf - rd0_r, b_rdf - rd0_b);
                errors = errors + 1;
            end
            // The counter advances on an RD# rising edge taken while CS# is
            // still low, i.e. between words of a burst. The last word of the
            // request raises RD# and CS# together, so a burst that needs
            // want_cs address latches shows 4 - want_cs advances: 3 for a
            // whole-request burst, 2 when it breaks at a 128K block. The
            // per-word path releases CS# with every RD#, so it never uses the
            // counter at all.
            if ((b_inc - in0_b) != (4 - want_cs)) begin
                $display("FAIL: cart counter advanced %0d times, expected %0d",
                         b_inc - in0_b, 4 - want_cs);
                errors = errors + 1;
            end
            if ((r_inc - in0_r) != 0) begin
                $display("FAIL: per-word path used the cart counter %0d times",
                         r_inc - in0_r);
                errors = errors + 1;
            end

            // 5. the address latched on each CS# fall
            for (k = 0; k < 4; k = k + 1) begin
                if (cart_ref.latch_log[cs0_r + k] !== (base + k)) begin
                    $display("FAIL: per-word latch %0d = %06h, expected %06h",
                             k, cart_ref.latch_log[cs0_r + k], base + k);
                    errors = errors + 1;
                end
            end
            if (cart_bst.latch_log[cs0_b] !== base) begin
                $display("FAIL: burst latched %06h on its first CS# fall, expected %06h",
                         cart_bst.latch_log[cs0_b], base);
                errors = errors + 1;
            end

            // 6. protocol
            if (b_eredr) fail("burst re-drove AD while CS# was low");
            if (r_erdcs || b_erdcs) fail("RD# strobed with CS# high");
            if (r_erdout || b_erdout) fail("RD# strobed while host drove AD");
        end
    endtask

    initial begin
        repeat (10) @(posedge clk);
        reset_n <= 1;
        repeat (4300) @(posedge clk);   // RESET_LEN

        // Ordinary requests, well away from a 128K block edge.
        check_read(25'h0000000, 1);
        check_read(25'h0000001, 1);
        check_read(25'h0000002, 1);
        check_read(25'h0012345, 1);
        check_read(25'h0abcdef, 1);
        check_read(25'h1234567, 1);
        check_read(25'h07f0010, 1);

        // Back to back, non-adjacent: the address must be re-latched for each
        // request, not carried over from the previous burst.
        check_read(25'h0000010, 1);
        check_read(25'h0100000, 1);
        check_read(25'h0000010, 1);

        // 128K block edge. base = 02FFFEh, so halfwords 2 and 3 live in the
        // next block and the cart's 16-bit counter would wrap to 020000h.
        // The burst must break here and re-drive: two CS# falls, and the data
        // must still match the per-word path.
        check_read(25'h0017fff, 2);
        check_read(25'h000ffff, 2);   // base = 01FFFEh, the GBATEK example

        if (seq_pulses != nwhole * 3 + (nreq - nwhole) * 2)
            fail("missing sequential pulse width checks");

        $display("");
        $display("CYCLES per 4-halfword request, whole-request burst (%0d requests): per-word %0d, burst %0d",
                 nwhole, whole_ref / nwhole, whole_bst / nwhole);
        $display("CYCLES per 4-halfword request, all %0d requests incl. 128K breaks: per-word %0d, burst %0d",
                 nreq, tot_ref / nreq, tot_bst / nreq);

        if (errors == 0)
            $display("PASS: all checks passed");
        else
            $display("FAIL: %0d check(s) failed", errors);
        $finish;
    end
endmodule
