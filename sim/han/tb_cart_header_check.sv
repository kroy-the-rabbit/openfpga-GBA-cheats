// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
module tb_cart_header_check;
    reg clk=0;
    always #5 clk=~clk;
    reg enable=0, req=0, ready=0;
    reg [24:0] addr=0;
    reg [31:0] first=0, second=0;
    wire [31:0] diagnostic, hd;
    wire [31:0] hs=diagnostic;
    reg [31:0] header[0:47];
    cart_header_check dut(clk,enable,req,addr,ready,first,second,diagnostic,hd);
    task restart;
        begin
            @(negedge clk);enable=0;req=0;ready=0;
            repeat(2) @(negedge clk);
            enable=1;
        end
    endtask
    integer response_delay=3;
    task pair_read(input [24:0] word_addr, input [31:0] xor_first, xor_second);
        begin
            @(negedge clk);addr=word_addr;req=1;
            @(negedge clk);req=0;addr=25'h1ffffff;
            repeat(response_delay) @(negedge clk);
            first=(word_addr<48 ? header[word_addr] : 32'h87654321)^xor_first;
            // Deliberately wrong on the ready edge: the cache consumes the
            // companion on the NEXT clock, when we present the real value.
            second=32'hbad0bad0;ready=1;
            @(negedge clk);ready=0;
            second=(word_addr<48 ? header[word_addr^1] : 32'h12345678)^xor_second;
            @(negedge clk);first=0;second=0;
        end
    endtask
    integer i;
    initial begin
        $readmemh("sim/fixtures/bmxe-header.hex",header);
        restart();
        for(i=47;i>=0;i=i-1) pair_read(i,0,0);
        if(hs!==32'h309a0000 || hd!==0) $fatal(1,"FAIL complete header %h %h",hs,hd);
        restart();
        response_delay=0; // Ready on the first clock after request acceptance.
        for(i=0;i<48;i=i+1) pair_read(i,0,0);
        if(hs!==32'h309a0000) $fatal(1,"FAIL minimum-latency header %h",hs);
        response_delay=3;
        pair_read(48,32'hffffffff,32'hffffffff);
        pair_read(25'h1000000,32'hffffffff,32'hffffffff);
        if(hs!==32'h309a0000) $fatal(1,"FAIL non-header alias counted");
        restart();
        pair_read(5,32'h00010000,32'h01000000);
        if(hs!==32'h013a1440 || hd!==(header[5]^32'h00010000))
            $fatal(1,"FAIL first beat priority %h %h",hs,hd);
        pair_read(2,32'hffffffff,32'hffffffff);
        if(hs!==32'h023a1440 || hd!==(header[5]^32'h00010000))
            $fatal(1,"FAIL first mismatch retention %h %h",hs,hd);
        restart();
        pair_read(9,32'hffffffff,0);
        if(hs!==32'h013a24f0) $fatal(1,"FAIL all lanes %h",hs);
        restart();
        pair_read(5,0,32'h00000001);
        if(hs!==32'h013a1011 || hd!==(header[4]^32'h00000001))
            $fatal(1,"FAIL odd companion address/lanes %h %h",hs,hd);
        restart();
        pair_read(4,0,32'h80000000);
        if(hs!==32'h013a1481 || hd!==(header[5]^32'h80000000))
            $fatal(1,"FAIL even companion address/lanes %h %h",hs,hd);
        restart();
        @(negedge clk);ready=1;
        @(negedge clk);ready=0;
        if(hs!==32'h004a0000) $fatal(1,"FAIL orphan response flag %h",hs);
        restart();
        @(negedge clk);addr=0;req=1;
        @(negedge clk);addr=1;
        @(negedge clk);req=0;
        if(!hs[22]) $fatal(1,"FAIL overlapping request flag");
        restart();
        // Check saturation without running 256 slow transactions.
        dut.checked_pairs=8'hfe;
        pair_read(0,0,0);pair_read(1,0,0);
        if(hs[31:24]!==8'hff) $fatal(1,"FAIL count saturation");
        restart();
        enable=0;pair_read(0,32'hffffffff,32'hffffffff);
        if(hs!==32'h000a0000 || hd!==0) $fatal(1,"FAIL disabled checker %h %h",hs,hd);
        $display("PASS header diagnostic: all 48 words, both beat cycles, corruption, retention, scope, reset and protocol guards");
        $finish;
    end
    initial begin #100000; $fatal(1,"FAIL header checker timeout"); end
endmodule
