// tb_gba_cart_controller.sv
//
// Behavioral cartridge model + test bench covering:
//   ROM reads, SRAM/Flash byte R/W, EEPROM bit forward, GPIO R/W.

`timescale 1ns / 1ps

module cart_rom_model (
    inout  wire [7:0] bank2,
    inout  wire [7:0] bank3,
    inout  wire [7:0] bank1,
    inout  wire [3:0] bank0,
    inout  wire       pin30
);
    wire rd_n  = bank0[1];
    wire cs_n  = bank0[0];
    wire wr_n  = bank0[2];
    // pin30 is CS2#/RES# 鈥?SRAM/Flash select only.
    wire cs2_n = pin30;

    // Address latch on CS1# falling edge (real cart latches A0-A23 there).
    // Use a small delay so the RTL's registered bank outputs (also clocked
    // at this edge) have settled on the bus.
    reg [23:0] addr_latch;
    always @(negedge cs_n) begin
        addr_latch <= #2 {bank1, bank2, bank3};
    end
    wire [15:0] rom_dout = addr_latch[15:0] ^ 16'hA55A;

    // SRAM (save region via CS2#): 16-bit address on AD, 8-bit data on A[23:16]
    reg [7:0] sram_mem [0:65535];
    reg [15:0] sram_addr_latch;
    always @(negedge cs2_n) begin
        sram_addr_latch <= {bank2, bank3};
    end
    integer i;
    initial begin
        for (i = 0; i < 65536; i = i + 1)
            sram_mem[i] = i[7:0] ^ 8'hA5;
    end
    always @(posedge wr_n) begin
        if (!cs2_n)
            sram_mem[sram_addr_latch] <= bank1;
    end
    wire [7:0] sram_dout = sram_mem[sram_addr_latch];

    // GPIO (16-bit access at 0x080000C4.. = halfword 0x04000062..,
    //       data in D3..D0)
    reg [3:0] gpio_reg [0:2];
    initial begin gpio_reg[0] = 4'h5; gpio_reg[1] = 4'h9; gpio_reg[2] = 4'h3; end
    reg [23:0] gpio_addr_latch;
    always @(negedge cs_n) begin
        gpio_addr_latch <= #2 {bank1, bank2, bank3};
    end
    // Decode halfword addresses 0x04000062/63/64 (GBA byte 0x080000C4/6/8).
    // The cartridge bus carries only the low 24 bits of the halfword address,
    // so 0x04000062 arrives as A[23:0] = 0x000062 (A[23:16] = 0x00); the 0x04
    // prefix lives above the 24-bit bus and is not visible to the cart.
    wire       gpio_sel = (gpio_addr_latch[15:8] == 8'h00) &&
                          (gpio_addr_latch[7:0] >= 8'h62) &&
                          (gpio_addr_latch[7:0] <= 8'h64);
    wire [1:0] gpio_idx = gpio_addr_latch[7:0] - 8'h62;  // 0x62/0x63/0x64 -> 0..2
    always @(posedge wr_n) begin
        if (!cs_n && gpio_sel)
            gpio_reg[gpio_idx] <= bank3[3:0];
    end

    // EEPROM: tiny model. While ROMCS# is low and A23 high, each RD# pulse
    // presents the next bit on D0; each WR# pulse samples D0. We return a
    // toggling pattern so the read handshake is observable.
    // eeprom_active distinguishes EEPROM (A23 latched high at CS1# falling
    // edge) from normal ROM accesses so the model drives D0 only for EEPROM.
    reg eeprom_d0_out;
    reg eeprom_active;
    initial eeprom_d0_out = 1'b0;
    initial eeprom_active = 1'b0;
    always @(negedge cs_n) begin
        eeprom_active <= (bank1[7] === 1'b1);
    end
    always @(posedge cs_n) begin
        eeprom_active <= 1'b0;
    end
    always @(negedge rd_n) begin
        if (!cs_n && eeprom_active)
            eeprom_d0_out <= ~eeprom_d0_out;
    end

    // Bus drive priority: GPIO / SRAM / ROM depending on active select
    reg [7:0] bank3_drv;
    reg       bank3_en;
    always @(*) begin
        if (!cs_n && eeprom_active && wr_n) begin
            // EEPROM owns D0 while selected (data stays valid after RD#
            // rises, per insideGadgets measurement); must out-prioritize ROM
            // because ROM also sees CS# low + RD# pulses.
            bank3_drv = {7'b0, eeprom_d0_out};
            bank3_en  = 1'b1;
        end else if (!cs_n && gpio_sel && wr_n) begin
            bank3_drv = {4'b0, gpio_reg[gpio_idx]};
            bank3_en  = 1'b1;
        end else if (!rd_n && !cs_n) begin
            bank3_drv = rom_dout[7:0];
            bank3_en  = 1'b1;
        end else begin
            bank3_drv = 8'hzz;
            bank3_en  = 1'b0;
        end
    end
    assign bank3 = bank3_en ? bank3_drv : 8'hzz;
    assign bank1 = (!eeprom_active && !rd_n && !cs2_n && cs_n) ? sram_dout : 8'hzz;
    assign bank2 = (!rd_n && !cs_n) ? rom_dout[15:8] : 8'hzz;
endmodule


module tb_gba_cart_controller;
    reg        clk = 0;
    reg        reset_n = 0;

    wire [7:0] cart_tran_bank2, cart_tran_bank3, cart_tran_bank1;
    wire       cart_tran_bank2_dir, cart_tran_bank3_dir, cart_tran_bank1_dir;
    wire [3:0] cart_tran_bank0;
    wire       cart_tran_bank0_dir;
    wire       cart_tran_pin30;
    wire       cart_tran_pin30_dir;
    wire       cart_pin30_pwroff_reset;
    wire       cart_tran_pin31;
    wire       cart_tran_pin31_dir;

    reg        rd_req = 0;
    reg  [24:0] rd_addr = 0;
    wire [31:0] rd_data;
    wire [31:0] rd_data_second;
    wire        rd_ready;

    reg        save_req = 0;
    reg  [16:0] save_addr = 0;
    reg        save_rnw = 1;
    reg  [7:0]  save_din = 0;
    wire [7:0]  save_dout;
    wire        save_done;

    reg        eeprom_req = 0;
    reg        eeprom_rnw = 1;
    reg        eeprom_din = 0;
    reg        eeprom_dma = 1;   // 1 = DMA3 burst, 0 = CPU poll
    wire       eeprom_dout;
    wire       eeprom_done;

    reg        gpio_req = 0;
    reg        gpio_rnw = 1;
    reg  [1:0] gpio_addr = 0;
    reg  [3:0] gpio_din = 0;
    wire [3:0] gpio_dout;
    wire       gpio_done;

    wire        cart_present;
    wire [7:0]  err_count;

    gba_cart_controller dut (
        .clk                    (clk),
        .reset_n                (reset_n),
        .cart_tran_bank2        (cart_tran_bank2),
        .cart_tran_bank2_dir    (cart_tran_bank2_dir),
        .cart_tran_bank3        (cart_tran_bank3),
        .cart_tran_bank3_dir    (cart_tran_bank3_dir),
        .cart_tran_bank1        (cart_tran_bank1),
        .cart_tran_bank1_dir    (cart_tran_bank1_dir),
        .cart_tran_bank0        (cart_tran_bank0),
        .cart_tran_bank0_dir    (cart_tran_bank0_dir),
        .cart_tran_pin30        (cart_tran_pin30),
        .cart_tran_pin30_dir    (cart_tran_pin30_dir),
        .cart_pin30_pwroff_reset(cart_pin30_pwroff_reset),
        .cart_tran_pin31        (cart_tran_pin31),
        .cart_tran_pin31_dir    (cart_tran_pin31_dir),
        .rd_req                 (rd_req),
        .rd_addr                (rd_addr),
        .rd_data                (rd_data),
        .rd_data_second         (rd_data_second),
        .rd_ready               (rd_ready),
        .save_req               (save_req),
        .save_addr              (save_addr),
        .save_rnw               (save_rnw),
        .save_din               (save_din),
        .save_dout              (save_dout),
        .save_done              (save_done),
        .eeprom_req             (eeprom_req),
        .eeprom_rnw             (eeprom_rnw),
        .eeprom_din             (eeprom_din),
        .eeprom_dma             (eeprom_dma),
        .eeprom_dout            (eeprom_dout),
        .eeprom_done            (eeprom_done),
        .gpio_req               (gpio_req),
        .gpio_rnw               (gpio_rnw),
        .gpio_addr              (gpio_addr),
        .gpio_din               (gpio_din),
        .gpio_dout              (gpio_dout),
        .gpio_done              (gpio_done),
        .cart_present           (cart_present),
        .err_count              (err_count)
    );

    cart_rom_model cart (
        .bank2 (cart_tran_bank2),
        .bank3 (cart_tran_bank3),
        .bank1 (cart_tran_bank1),
        .bank0 (cart_tran_bank0),
        .pin30 (cart_tran_pin30)
    );

    always #5 clk = ~clk;   // 100 MHz

    integer errors = 0;

    initial begin
        repeat (10) @(posedge clk);
        reset_n <= 1;
        repeat (4200) @(posedge clk);

        // ---- ROM read regression (byte 0) ----
        @(posedge clk);
        rd_req <= 1; rd_addr <= 25'd0;
        @(posedge clk);
        rd_req <= 0;
        wait (rd_ready);
        @(posedge clk);
        if (rd_data !== 32'hA55B_A55A || rd_data_second !== 32'hA559_A558) begin
            $display("FAIL: ROM read");
            errors = errors + 1;
        end
        // ---- SRAM write + read-back (data on A[23:16], addr on AD[15:0]) ----
        @(posedge clk);
        save_req <= 1; save_addr <= 17'h1234; save_rnw <= 0; save_din <= 8'hAB;
        @(posedge clk);
        save_req <= 0;
        wait (save_done);
        @(posedge clk);

        @(posedge clk);
        save_req <= 1; save_addr <= 17'h1234; save_rnw <= 1;
        @(posedge clk);
        save_req <= 0;
        wait (save_done);
        @(posedge clk);
        if (save_dout !== 8'hAB) begin
            $display("FAIL: SRAM read-back got %02h expected AB", save_dout);
            errors = errors + 1;
        end

        // ---- GPIO read ----
        @(posedge clk);
        gpio_req <= 1; gpio_rnw <= 1; gpio_addr <= 2'd1;
        @(posedge clk);
        gpio_req <= 0;
        wait (gpio_done);
        @(posedge clk);
        if (gpio_dout !== 4'h9) begin
            $display("FAIL: GPIO read got %h expected 9", gpio_dout);
            errors = errors + 1;
        end

        // ---- GPIO write + read-back ----
        @(posedge clk);
        gpio_req <= 1; gpio_rnw <= 0; gpio_addr <= 2'd2; gpio_din <= 4'h7;
        @(posedge clk);
        gpio_req <= 0;
        wait (gpio_done);
        @(posedge clk);
        @(posedge clk);
        gpio_req <= 1; gpio_rnw <= 1; gpio_addr <= 2'd2;
        @(posedge clk);
        gpio_req <= 0;
        wait (gpio_done);
        @(posedge clk);
        if (gpio_dout !== 4'h7) begin
            $display("FAIL: GPIO write read-back got %h expected 7", gpio_dout);
            errors = errors + 1;
        end

        // ---- EEPROM bit forward (write then read; must complete without hang) ----
        @(posedge clk);
        eeprom_req <= 1; eeprom_rnw <= 0; eeprom_din <= 1'b1;
        @(posedge clk);
        eeprom_req <= 0;
        wait (eeprom_done);
        @(posedge clk);

        // ---- EEPROM session hold: consecutive bits must keep CS1# low / A23 high ----
        // First bit just completed; session is still open (within timeout).
        if (cart_tran_bank0[0] !== 1'b0 || cart_tran_bank1 !== 8'h80) begin
            $display("FAIL: EEPROM session not held after bit (cs1=%b bank1=%h)",
                     cart_tran_bank0[0], cart_tran_bank1);
            errors = errors + 1;
        end
        @(posedge clk);
        eeprom_req <= 1; eeprom_rnw <= 0; eeprom_din <= 1'b0;
        @(posedge clk);
        eeprom_req <= 0;
        wait (eeprom_done);
        @(posedge clk);
        // Session should still be held during the burst.
        if (cart_tran_bank0[0] !== 1'b0 || cart_tran_bank1 !== 8'h80) begin
            $display("FAIL: EEPROM session dropped mid-burst (cs1=%b bank1=%h)",
                     cart_tran_bank0[0], cart_tran_bank1);
            errors = errors + 1;
        end

        // ---- EEPROM write->read burst transition ----
        // The read/write command is a burst of write bits (rnw=0); the data
        // burst follows with rnw=1. The controller must pulse /CS high once
        // on that transition so the cart chip latches the command, then pull
        // it low again for the read burst. Verify a /CS high pulse happens
        // before the read completes (no timeout between the bursts).
        begin
            reg saw_cs_high;
            saw_cs_high = 0;
            @(posedge clk);
            eeprom_req <= 1; eeprom_rnw <= 1;
            @(posedge clk);
            eeprom_req <= 0;
            while (!eeprom_done) begin
                @(posedge clk);
                if (cart_tran_bank0[0] === 1'b1) saw_cs_high = 1;
            end
            @(posedge clk);
            if (!saw_cs_high) begin
                $display("FAIL: EEPROM write->read transition did not pulse /CS high");
                errors = errors + 1;
            end
            // model drives a real 0/1 on D0 (toggles per RD# pulse); just check
            // the handshake returned valid data instead of high-Z.
            if (eeprom_dout !== 1'b0 && eeprom_dout !== 1'b1) begin
                $display("FAIL: EEPROM read bit got %b (not 0/1)", eeprom_dout);
                errors = errors + 1;
            end
        end

        // Let the session timeout expire, then verify release.
        repeat (1100) @(posedge clk);
        if (cart_tran_bank0[0] !== 1'b1) begin
            $display("FAIL: EEPROM session not released after timeout (cs1=%b)",
                     cart_tran_bank0[0]);
            errors = errors + 1;
        end

        // ---- EEPROM CPU poll (write-complete ready polling) ----
        // A standalone CPU LDRH/STRH access (eeprom_dma=0) must be its own
        // /CS low-high cycle: after the bit completes, /CS returns high so the
        // cart chip can update its busy/ready status.
        @(posedge clk);
        eeprom_req <= 1; eeprom_rnw <= 1; eeprom_dma <= 0;
        @(posedge clk);
        eeprom_req <= 0;
        wait (eeprom_done);
        @(posedge clk);
        repeat (8) @(posedge clk);
        if (cart_tran_bank0[0] !== 1'b1) begin
            $display("FAIL: EEPROM CPU poll left /CS low (cs1=%b)", cart_tran_bank0[0]);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: all checks passed");
        else
            $display("FAIL: %0d check(s) failed", errors);
        $finish;
    end
endmodule

