// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
module eeprom_bridge_case #(parameter ADDR_BITS=14, parameter PROGRAM_BUSY_POLLS=0, parameter DMA_FALL_ON_DONE=0)(output reg finished=0);
    localparam [ADDR_BITS-1:0] BLOCK37=37, BLOCK39=39;
    localparam READ_BITS=ADDR_BITS+3, WRITE_BITS=ADDR_BITS+67;
    reg clk=0, reset_n=0;
    always #5 clk=~clk;
    reg host_req=0, host_rnw=1, host_din=0, host_dma=1, host_last=1;
    // DMA3 remains active across individual request/response gaps.
    reg host_dma_active=1;
    reg [16:0] host_count=0;
    wire host_dout, host_done, fault;
    wire ctl_req, ctl_rnw, ctl_din, ctl_dma, ctl_dout, ctl_done;
    wire [7:0] bank1,bank2,bank3;
    wire [7:4] bank0;
    wire pin30,pin31;
    integer transfers=0, write_edges=0;
    always @(posedge clk) if(ctl_req) transfers=transfers+1;
    always @(negedge bank0[6]) if(reset_n) write_edges=write_edges+1;
    cart_eeprom_bridge bridge (
        .clk(clk), .reset_n(reset_n), .fault(fault),
        .host_req(host_req), .host_rnw(host_rnw), .host_din(host_din),
        .host_dma(host_dma), .host_dma_active(host_dma_active),
        .host_last(host_last), .host_count(host_count),
        .host_dout(host_dout), .host_done(host_done),
        .ctl_req(ctl_req), .ctl_rnw(ctl_rnw), .ctl_din(ctl_din), .ctl_dma(ctl_dma),
        .ctl_dout(ctl_dout), .ctl_done(ctl_done)
    );
    gba_cart_controller #(.RESET_LEN(8)) dut (
        .rom_profile(3'd0),
        .clk(clk), .reset_n(reset_n), .phi_sel(2'b0),
        .cart_tran_bank1(bank1), .cart_tran_bank2(bank2), .cart_tran_bank3(bank3),
        .cart_tran_bank0(bank0), .cart_tran_pin30(pin30), .cart_tran_pin31(pin31),
        .rd_req(1'b0), .rd_addr(25'b0),
        .save_req(1'b0), .save_addr(17'b0), .save_rnw(1'b1), .save_din(8'b0),
        .eeprom_req(ctl_req), .eeprom_rnw(ctl_rnw), .eeprom_din(ctl_din),
        .eeprom_dma(ctl_dma), .eeprom_dout(ctl_dout), .eeprom_done(ctl_done),
        .gpio_req(1'b0), .gpio_rnw(1'b1), .gpio_addr(2'b0), .gpio_din(4'b0),
        .gpio_timing_mode(3'b0), .gpio_recover_set(14'b0)
    );
    cart_eeprom_model #(.ADDR_BITS(ADDR_BITS), .BUSY_POLLS(PROGRAM_BUSY_POLLS)) cart (
        .cs_n(bank0[4]), .rd_n(bank0[5]), .wr_n(bank0[6]), .a23(bank1[7]), .d0(bank3[0])
    );
    task automatic bit_access(input rnw,input din,input dma,input last,input [16:0] count,output dout);
        integer timeout;
        begin
            @(negedge clk);
            if(DMA_FALL_ON_DONE && dma) host_dma_active=1;
            host_req=1;host_rnw=rnw;host_din=din;host_dma=dma;host_last=last;host_count=count;
            @(negedge clk); host_req=0;
            // The host payload is only valid with its request. The bridge
            // must own and hold the controller payload until completion.
            host_rnw=~rnw;host_din=~din;host_dma=~dma;host_last=~last;host_count=0;
            timeout=0;
            while(!host_done && timeout<5000) begin @(negedge clk);timeout=timeout+1;end
            if(!host_done) $fatal(1,"FAIL: EEPROM bridge host timeout");
            dout=host_dout;
            // DMA3 may fall inactive on the same clock the bridge observes
            // final host_done. A completed command must not latch a fault.
            if(DMA_FALL_ON_DONE && dma && last) host_dma_active=0;
            @(negedge clk);
        end
    endtask
    reg ignored;
    task automatic send_command(input [80:0] value,input integer count,input integer toggle_after);
        integer i;
        begin
            for(i=count-1;i>=0;i=i-1) begin
                bit_access(0,value[i],1,i==0,count,ignored);
            end
        end
    endtask
    task automatic read_block(input [13:0] addr,input [63:0] expected);
        integer i;
        reg bit_value;
        reg [63:0] result;
        begin
            send_command({2'b11,addr[ADDR_BITS-1:0],1'b0},READ_BITS,-1);
            if(bank0[4] !== 1'b1) $fatal(1,"FAIL: read command final bit did not close EEPROM session");
            result=0;
            for(i=0;i<68;i=i+1) begin
                bit_access(1,0,1,i==67,68,bit_value);
                if(i>=4) result={result[62:0],bit_value};
            end
            if(result !== expected) $fatal(1,"FAIL: bridge existing-save block %0d got %h expected %h",addr,result,expected);
        end
    endtask
    // Real chips return zero while programming, then one. Polling must
    // preserve those zeros and close CS after every standalone CPU access.
    task automatic poll_program;
        integer polls;
        reg ready_bit;
        begin
            for(polls=0;polls<=PROGRAM_BUSY_POLLS;polls=polls+1) begin
                bit_access(1,0,0,1,0,ready_bit);
                if(ready_bit !== (polls==PROGRAM_BUSY_POLLS) || bank0[4]!==1)
                    $fatal(1,"FAIL: EEPROM busy/ready poll %0d returned %b",polls,ready_bit);
            end
        end
    endtask
    integer before_transfers, before_edges;
    reg [63:0] original,neighbor;
    initial begin
        repeat(5) @(negedge clk); reset_n=1; repeat(20) @(negedge clk);
        original=cart.mem[37];neighbor=cart.mem[38];
        before_transfers=transfers;before_edges=write_edges;
        // An existing save reads back untouched, then programs.
        read_block(37,original);
        if(cart.writes!=0) $fatal(1,"FAIL: existing save read programmed EEPROM");
        send_command({2'b10,BLOCK37,64'h0123_4567_89ab_cdef,1'b0},WRITE_BITS,-1);
        if(cart.writes!=1 || cart.mem[37]!==64'h0123_4567_89ab_cdef || bank0[4]!==1)
            $fatal(1,"FAIL: write completion or explicit final-bit boundary");
        if(PROGRAM_BUSY_POLLS>0) poll_program();
        read_block(37,64'h0123_4567_89ab_cdef);
        // Same-direction DMA commands back to back must remain separate.
        send_command({2'b10,BLOCK37,64'hfeca_ba98_7654_3210,1'b0},WRITE_BITS,-1);
        if(PROGRAM_BUSY_POLLS>0) poll_program();
        send_command({2'b10,BLOCK39,64'hc35a_e718_049b_d26f,1'b0},WRITE_BITS,-1);
        if(PROGRAM_BUSY_POLLS>0) poll_program();
        bit_access(1,0,0,1,0,ignored);
        if(ignored!==1 || bank0[4]!==1) $fatal(1,"FAIL: bridge CPU ready polling");
        read_block(37,64'hfeca_ba98_7654_3210);
        read_block(39,64'hc35a_e718_049b_d26f);
        if(cart.writes!=3 || cart.mem[38]!==neighbor) $fatal(1,"FAIL: write count or adjacent block preservation");
        host_dma_active=0;
        repeat(4) @(negedge clk);
        if(fault !== 0) $fatal(1,"FAIL: completed DMA going inactive latched abort fault");
        // Reset only the FPGA host; the cartridge keeps its programmed
        // storage. Reading after restart must use that storage again.
        @(negedge clk); reset_n=0;
        repeat(5) @(negedge clk); reset_n=1;
        repeat(20) @(negedge clk);
        host_dma_active=1;
        read_block(37,64'hfeca_ba98_7654_3210);
        read_block(39,64'hc35a_e718_049b_d26f);
        if(cart.writes!=3 || cart.mem[38]!==neighbor)
            $fatal(1,"FAIL: programmed saves changed across FPGA reset");
        if(fault !== 0) $fatal(1,"FAIL: normal completed EEPROM traffic latched abort fault");
        $display("PASS: %0d-bit EEPROM busy polls=%0d, DMA fall at done=%0d and readback after FPGA reset",ADDR_BITS,PROGRAM_BUSY_POLLS,DMA_FALL_ON_DONE);
        $display("PASS: %0d-bit EEPROM bridge existing saves and physical program/readback", ADDR_BITS);
        finished=1;
    end
endmodule

module tb_cart_eeprom_bridge;
    wire small_done, large_done, busy_done, dma_fall_done;
    eeprom_bridge_case #(.ADDR_BITS(6)) small_cart(small_done);
    eeprom_bridge_case #(.ADDR_BITS(14)) large_cart(large_done);
    eeprom_bridge_case #(.ADDR_BITS(14), .PROGRAM_BUSY_POLLS(3)) busy_cart(busy_done);
    eeprom_bridge_case #(.ADDR_BITS(14), .PROGRAM_BUSY_POLLS(3), .DMA_FALL_ON_DONE(1)) dma_fall_cart(dma_fall_done);
    initial begin wait(small_done && large_done && busy_done && dma_fall_done); $finish; end
    initial begin #10000000; $fatal(1,"FAIL: EEPROM bridge watchdog"); end
endmodule
