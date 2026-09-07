// SPDX-License-Identifier: GPL-3.0-or-later
// Pin-level EEPROM command model, including existing-save reads. Unlike a
// toggling-bit fixture, only a complete serial command selects the saved block.
`timescale 1ns/1ps
module cart_eeprom_model #(parameter ADDR_BITS = 14)(
    input wire cs_n, rd_n, wr_n, a23,
    inout wire d0
);
    localparam BLOCKS = (ADDR_BITS == 6) ? 64 : 1024;
    reg [63:0] mem [0:BLOCKS-1];
    reg [80:0] command;
    integer command_bits = 0;
    integer read_index = 0;
    integer selected_block = 0;
    integer writes = 0;
    reg selected = 0;
    reg read_pending = 0;
    reg output_enable = 0;
    reg output_bit = 1;
    time a23_high_since = 0;
    always @(a23) if (a23 === 1'b1) a23_high_since = $time;
    integer i;
    initial begin
        for (i = 0; i < BLOCKS; i = i + 1)
            mem[i] = 64'h935A_C761_2EF0_480D ^ (64'h0101_0202_0303_0404 * i);
    end
    assign d0 = output_enable ? output_bit : 1'bz;
    always @(negedge cs_n) begin
        selected = (a23 === 1'b1);
        if (selected && $time - a23_high_since < 20)
            $fatal(1, "FAIL: EEPROM CS fell before A23 address setup");
        command_bits = 0;
        command = 0;
        read_index = 0;
    end
    always @(posedge wr_n) begin
        if (selected && !cs_n) begin
            if (d0 !== 1'b0 && d0 !== 1'b1)
                $fatal(1, "FAIL: EEPROM write sampled undriven/contended D0");
            command = (command << 1) | d0;
            command_bits = command_bits + 1;
        end
    end
    always @(posedge cs_n) begin
        if (selected && command_bits != 0) begin
            if (command_bits == ADDR_BITS + 3 &&
                (command >> (ADDR_BITS + 1)) == 2'b11 && command[0] == 0) begin
                selected_block = (command >> 1) & (BLOCKS-1);
                read_pending = 1;
            end else if (command_bits == ADDR_BITS + 67 &&
                         (command >> (ADDR_BITS + 65)) == 2'b10 && command[0] == 0) begin
                selected_block = (command >> 65) & (BLOCKS-1);
                mem[selected_block] = command >> 1;
                writes = writes + 1;
                read_pending = 0;
            end else begin
                $fatal(1, "FAIL: invalid EEPROM command (%0d address bits): length=%0d value=%h",
                    ADDR_BITS, command_bits, command);
            end
        end
        selected = 0;
        output_enable = 0;
    end
    always @(negedge rd_n) begin
        if (selected && !cs_n) begin
            output_enable = 1;
            if (read_pending) begin
                output_bit = (read_index < 4) ? 0 : mem[selected_block][67-read_index];
                read_index = read_index + 1;
                if (read_index == 68) read_pending = 0;
            end else output_bit = 1; // programming complete / CPU ready poll
        end
    end
    // No guaranteed hold time after RD rises: sample while RD is low.
    // This catches reading the released cartridge bus one clock too late.
    always @(posedge rd_n) output_enable <= 0;
endmodule

module cart_save_case #(parameter ADDR_BITS = 14)(output reg finished = 0);
    reg clk = 0, reset_n = 0;
    always #5 clk = ~clk;
    wire [7:0] bank1, bank2, bank3;
    wire [7:4] bank0;
    wire pin30, pin31;
    reg ee_req = 0, ee_rnw = 1, ee_din = 0, ee_dma = 1;
    wire ee_dout, ee_done;
    reg save_req = 0, save_rnw = 1;
    reg [16:0] save_addr = 0;
    reg [7:0] save_din = 0;
    wire [7:0] save_dout;
    wire save_done;
    reg [7:0] sram [0:65535];
    integer sram_writes = 0;
    integer i;
    initial for (i=0; i<65536; i=i+1) sram[i] = i[7:0] ^ 8'h5a;
    assign bank1 = (!pin30 && !bank0[5] && bank0[4]) ? sram[{bank2,bank3}] : 8'hzz;
    always @(posedge bank0[6]) if (!pin30 && bank0[4] && reset_n) begin
        if ((^bank1) === 1'bx || (^{bank2,bank3}) === 1'bx)
            $fatal(1, "FAIL: SRAM write data/address invalid");
        sram[{bank2,bank3}] = bank1;
        sram_writes = sram_writes + 1;
    end
    gba_cart_controller #(.RESET_LEN(8)) dut (
        .clk(clk), .reset_n(reset_n), .phi_sel(2'b0),
        .cart_tran_bank1(bank1), .cart_tran_bank2(bank2), .cart_tran_bank3(bank3),
        .cart_tran_bank0(bank0), .cart_tran_pin30(pin30), .cart_tran_pin31(pin31),
        .rd_req(1'b0), .rd_addr(25'b0),
        .save_req(save_req), .save_addr(save_addr), .save_rnw(save_rnw),
        .save_din(save_din), .save_dout(save_dout), .save_done(save_done),
        .eeprom_req(ee_req), .eeprom_rnw(ee_rnw), .eeprom_din(ee_din),
        .eeprom_dma(ee_dma), .eeprom_dout(ee_dout), .eeprom_done(ee_done),
        .gpio_req(1'b0), .gpio_rnw(1'b1), .gpio_addr(2'b0), .gpio_din(4'b0),
        .gpio_timing_mode(3'b0), .gpio_recover_set(14'b0)
    );
    cart_eeprom_model #(.ADDR_BITS(ADDR_BITS)) cart (
        .cs_n(bank0[4]), .rd_n(bank0[5]), .wr_n(bank0[6]), .a23(bank1[7]), .d0(bank3[0])
    );
    task automatic ee_bit(input rnw, input din, input dma, output dout);
        integer timeout;
        begin
            @(negedge clk); ee_req=1; ee_rnw=rnw; ee_din=din; ee_dma=dma;
            @(negedge clk); ee_req=0;
            // The controller must latch the payload on request acceptance.
            ee_rnw=~rnw; ee_din=~din; ee_dma=~dma;
            timeout=0;
            while (!ee_done && timeout<2000) begin @(negedge clk); timeout=timeout+1; end
            if (!ee_done) $fatal(1, "FAIL: EEPROM request timed out");
            dout=ee_dout;
            @(negedge clk);
        end
    endtask
    reg ignored;
    task automatic ee_address(input read_command, input integer addr);
        integer bit_index;
        begin
            ee_bit(0,1,1,ignored); ee_bit(0,read_command,1,ignored);
            for(bit_index=ADDR_BITS-1; bit_index>=0; bit_index=bit_index-1)
                ee_bit(0,(addr >> bit_index)&1,1,ignored);
        end
    endtask
    task automatic read_block(input integer addr, input [63:0] expected);
        reg bit_value;
        reg [63:0] result;
        integer bit_index;
        begin
            ee_address(1,addr); ee_bit(0,0,1,ignored);
            for(bit_index=0; bit_index<4; bit_index=bit_index+1) ee_bit(1,0,1,ignored);
            result=0;
            for(bit_index=0; bit_index<64; bit_index=bit_index+1) begin
                ee_bit(1,0,1,bit_value); result={result[62:0],bit_value};
            end
            if(result !== expected) $fatal(1,"FAIL: EEPROM %0d-bit block %0d got %h expected %h",ADDR_BITS,addr,result,expected);
        end
    endtask
    task automatic byte_access(input rnw, input [16:0] addr, input [7:0] value);
        integer timeout;
        begin
            @(negedge clk); save_req=1; save_rnw=rnw; save_addr=addr; save_din=value;
            @(negedge clk); save_req=0;
            timeout=0;
            while(!save_done && timeout<2000) begin @(negedge clk); timeout=timeout+1; end
            if(!save_done) $fatal(1,"FAIL: SRAM byte request timed out");
            if(rnw && save_dout !== value) $fatal(1,"FAIL: SRAM %h got %h expected %h",addr,save_dout,value);
            @(negedge clk);
        end
    endtask
    reg [63:0] saved_neighbor;
    reg ready_bit;
    integer bit_index;
    initial begin
        repeat(5) @(negedge clk); reset_n=1; repeat(20) @(negedge clk);
        saved_neighbor=cart.mem[38];
        read_block(37,cart.mem[37]);
        read_block((ADDR_BITS==6)?63:1023,cart.mem[(ADDR_BITS==6)?63:1023]);
        if(cart.writes != 0) $fatal(1,"FAIL: reading existing save changed EEPROM");
        ee_address(0,37);
        for(bit_index=63;bit_index>=0;bit_index=bit_index-1)
            ee_bit(0,(64'hD276_0B95_A8E1_3FC4 >> bit_index)&1,1,ignored);
        ee_bit(0,0,1,ignored);
        ee_bit(1,0,0,ready_bit);
        if(ready_bit !== 1 || bank0[4] !== 1) $fatal(1,"FAIL: EEPROM CPU ready poll or session release");
        read_block(37,64'hD276_0B95_A8E1_3FC4);
        if(cart.writes != 1 || cart.mem[38] !== saved_neighbor)
            $fatal(1,"FAIL: EEPROM write count or neighboring save preservation");
        repeat(1100) @(negedge clk);
        byte_access(1,17'h1234,8'h6e);
        byte_access(0,17'h1234,8'hb7);
        byte_access(1,17'h1234,8'hb7);
        byte_access(1,17'h1235,8'h6f);
        if(sram_writes != 1) $fatal(1,"FAIL: SRAM write pulse count");
        $display("PASS: %0d-bit EEPROM existing-save read/program/readback/poll and SRAM preservation",ADDR_BITS);
        finished=1;
    end
endmodule

module tb_gba_cart_save;
    wire small_done, large_done;
    cart_save_case #(.ADDR_BITS(6)) small_cart(small_done);
    cart_save_case #(.ADDR_BITS(14)) large_cart(large_done);
    initial begin wait(small_done && large_done); $finish; end
    initial begin #10000000; $fatal(1,"FAIL: save test watchdog"); end
endmodule
