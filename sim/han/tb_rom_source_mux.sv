`timescale 1ns / 1ps

// Exercise cache.vhd's two-DWORD cache-line contract through the real cart
// controller. The second DWORD belongs to the same aligned 8-byte line,
// including when the requested DWORD is the upper half of that line.
module tb_rom_source_mux;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset_n = 0;
    reg cart_mode = 0, req = 0;
    reg [24:0] addr = 0;
    wire ready, sreq, creq, cready;
    wire [24:0] saddr, caddr;
    wire [31:0] data1, data2, cdata1, cdata2;
    reg sready = 0;

    rom_source_mux mux (
        .clk(clk), .cart_mode(cart_mode),
        .gba_rd_req(req), .gba_rd_addr(addr), .gba_rd_ready(ready),
        .gba_rd_data(data1), .gba_rd_data_second(data2),
        .sdram_rd_req(sreq), .sdram_rd_addr(saddr), .sdram_rd_ready(sready),
        .sdram_rd_data(32'h12345678), .sdram_rd_data_second(32'h9abcdef0),
        .cart_rd_req(creq), .cart_rd_addr(caddr), .cart_rd_ready(cready),
        .cart_rd_data(cdata1), .cart_rd_data_second(cdata2)
    );

    wire [7:0] b1, b2, b3;
    wire [3:0] b0;
    wire b2dir, b3dir;
    wire redrive, no_cs, while_out;
    gba_cart_controller controller (
        .clk(clk), .reset_n(reset_n), .phi_sel(2'd0),
        .cart_tran_bank1(b1), .cart_tran_bank2(b2), .cart_tran_bank3(b3),
        .cart_tran_bank0(b0),
        .cart_tran_bank2_dir(b2dir), .cart_tran_bank3_dir(b3dir),
        .rd_req(creq), .rd_addr(caddr), .rd_ready(cready),
        .rd_data(cdata1), .rd_data_second(cdata2),
        .save_req(1'b0), .save_addr(17'd0), .save_rnw(1'b1), .save_din(8'd0),
        .eeprom_req(1'b0), .eeprom_rnw(1'b1), .eeprom_din(1'b0), .eeprom_dma(1'b0),
        .gpio_req(1'b0), .gpio_rnw(1'b1), .gpio_addr(2'd0), .gpio_din(4'd0),
        .gpio_timing_mode(3'd0), .gpio_recover_set(14'd0)
    );
    cart_seq_rom_model cart (
        .bank1(b1), .bank2(b2), .bank3(b3), .bank0(b0),
        .bank2_dir(b2dir), .bank3_dir(b3dir),
        .err_redrive(redrive), .err_rd_no_cs(no_cs), .err_rd_while_out(while_out)
    );

    function [31:0] expected_dword(input [24:0] a);
        reg [23:0] halfaddr;
        reg [15:0] lo, hi;
        begin
            halfaddr = a << 1;
            lo = (halfaddr[15:0] * 16'h9e37) ^ 16'hc0de ^ {8'd0, halfaddr[23:16]};
            halfaddr = halfaddr + 1'b1;
            hi = (halfaddr[15:0] * 16'h9e37) ^ 16'hc0de ^ {8'd0, halfaddr[23:16]};
            expected_dword = {hi, lo};
        end
    endfunction

    integer cases = 0;
    task read_line(input [24:0] requested);
        reg [63:0] cache_line;
        begin
            @(negedge clk);
            addr = requested;
            req = 1;
            @(negedge clk);
            req = 0;
            // The response ordering must use the accepted request, not the
            // current address wires. Flip parity while the cart is busy.
            addr = requested ^ 25'd1;
            @(posedge ready);
            @(posedge clk);
            if (data1 !== expected_dword(requested))
                $fatal(1, "FAIL requested DWORD %h: got %h expected %h",
                       requested, data1, expected_dword(requested));
            if (requested[0]) cache_line[63:32] = data1;
            else              cache_line[31:0] = data1;
            // cache.vhd consumes the second DWORD on the following clock.
            @(posedge clk);
            if (data2 !== expected_dword(requested ^ 25'd1))
                $fatal(1, "FAIL companion DWORD for %h: got %h expected %h",
                       requested, data2, expected_dword(requested ^ 25'd1));
            if (requested[0]) cache_line[31:0] = data2;
            else              cache_line[63:32] = data2;
            if (cache_line !== {expected_dword(requested | 25'd1),
                                expected_dword(requested & ~25'd1)})
                $fatal(1, "FAIL reconstructed cache line");
            cases = cases + 1;
        end
    endtask

    integer i;
    initial begin
        repeat (4) @(negedge clk);
        reset_n = 1;
        // SDRAM must retain its existing address and response semantics.
        req = 1; addr = 25'h12345; sready = 1;
        #1;
        if (sreq !== 1'b1 || creq !== 1'b0 || saddr !== addr ||
            ready !== 1'b1 || data1 !== 32'h12345678 || data2 !== 32'h9abcdef0)
            $fatal(1, "FAIL SDRAM forwarding");
        @(negedge clk);
        req = 0; sready = 0; cart_mode = 1;
        read_line(25'd0);
        read_line(25'd1);
        read_line(25'h7fff);   // last DWORD before a 128 KiB cart boundary
        read_line(25'h8000);
        read_line(25'h8001);
        read_line(25'h7fffff); // last DWORD in 32 MiB ROM space
        for (i = 2; i < 66; i = i + 1) read_line(i);
        if (redrive || no_cs || while_out)
            $fatal(1, "FAIL cartridge pin protocol");
        $display("PASS ROM mux: %0d cache-line reads and SDRAM forwarding", cases);
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "FAIL timeout waiting for cache-line response");
    end
endmodule
