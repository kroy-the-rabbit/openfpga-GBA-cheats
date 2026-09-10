// SPDX-License-Identifier: GPL-3.0-or-later
// rom_patch: table fill from the loader push, substitution on both words of
// a line, byte masks, RAM entries ignored, reset clears.
`timescale 1ns/1ps
module tb_rom_patch;
    reg clk=0; always #5 clk=~clk;
    reg load_reset=1, cheat_on=0; reg [127:0] cheat_in=0;
    reg [24:0] rd_addr=0; reg [31:0] din_first=32'h11223344, din_second=32'h55667788;
    wire [31:0] dout_first, dout_second; wire [3:0] count;
    rom_patch dut(.clk(clk),.load_reset(load_reset),.cheat_on(cheat_on),.cheat_in(cheat_in),
        .rd_addr(rd_addr),.din_first(din_first),.din_second(din_second),
        .dout_first(dout_first),.dout_second(dout_second),.count(count));
    task push(input [27:0] addr, input [31:0] val, input [3:0] be, input [3:0] opt);
        begin
            @(negedge clk); cheat_in={24'd0,be,opt,4'd0,addr,32'd0,val};
            @(negedge clk); cheat_on=1;
            @(negedge clk); @(negedge clk); cheat_on=0;
            @(negedge clk);
        end
    endtask
    task read(input [24:0] a);
        begin rd_addr=a; @(negedge clk); @(negedge clk); @(negedge clk); end
    endtask
    initial begin
        repeat(3) @(negedge clk); load_reset=0;
        // D00D at byte 0800958A: dword 0x2562, upper halfword
        push(28'h800958A, 32'hD00D0000, 4'hC, 4'd0);
        // one byte at 0A000001 (mirror of 08000001): dword 0, lane 1
        push(28'hA000001, 32'h0000AA00, 4'h2, 4'd0);
        // RAM write, must not take a slot
        push(28'h3001538, 32'h000003E7, 4'h3, 4'd0);
        // conditional on ROM, must not take a slot
        push(28'h8000010, 32'h1, 4'h3, 4'd1);
        if (count!==2) $fatal(1,"FAIL slot count %0d, expected 2", count);
        read(25'h2562);
        if (dout_first!==32'hD00D3344 || dout_second!==32'h55667788)
            $fatal(1,"FAIL first-word patch %h %h", dout_first, dout_second);
        read(25'h2563);   // odd: partner is 0x2562, patched in the second word
        if (dout_first!==32'h11223344 || dout_second!==32'hD00D7788)
            $fatal(1,"FAIL partner patch %h %h", dout_first, dout_second);
        read(25'd0);
        if (dout_first!==32'h1122AA44) $fatal(1,"FAIL byte-lane patch %h", dout_first);
        read(25'h2564);
        if (dout_first!==32'h11223344 || dout_second!==32'h55667788)
            $fatal(1,"FAIL untouched read altered %h %h", dout_first, dout_second);
        load_reset=1; @(negedge clk); load_reset=0;
        read(25'h2562);
        if (count!==0 || dout_first!==32'h11223344) $fatal(1,"FAIL reset did not clear the table");
        $display("PASS rom_patch: fill from the push, both words, byte lanes, RAM and conditional entries ignored, reset");
        $finish;
    end
    initial begin #200000; $fatal(1,"rom_patch watchdog"); end
endmodule
