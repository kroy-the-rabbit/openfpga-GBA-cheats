// SPDX-License-Identifier: GPL-3.0-or-later
// rom_patch: table fill from the loader push, substitution on both words of
// a line, byte masks, RAM entries ignored, reset clears.
`timescale 1ns/1ps
module tb_rom_patch;
    reg clk=0; always #5 clk=~clk;
    reg load_reset=1, cheat_on=0; reg [127:0] cheat_in=0;
    reg rd_req=0; reg [24:0] rd_addr=0; reg [31:0] din_first=32'h11223344, din_second=32'h55667788;
    reg rd_ready=0; wire rd_ready_out;
    wire [31:0] dout_first, dout_second; wire [4:0] count; wire changed; integer changes=0, n=0;
    always @(posedge clk) if (changed) changes=changes+1;
    rom_patch dut(.clk(clk),.load_reset(load_reset),.cheat_on(cheat_on),.cheat_in(cheat_in),
        .rd_req(rd_req),.rd_addr(rd_addr),.din_first(din_first),.din_second(din_second),
        .rd_ready(rd_ready),.dout_first(dout_first),.dout_second(dout_second),
        .rd_ready_out(rd_ready_out),.count(count),.changed(changed));
    task push(input [27:0] addr, input [31:0] val, input [3:0] be, input [3:0] opt);
        begin
            @(negedge clk); cheat_in={24'd0,be,opt,4'd0,addr,32'd0,val};
            @(negedge clk); cheat_on=1;
            @(negedge clk); @(negedge clk); cheat_on=0;
            @(negedge clk);
        end
    endtask
    // Request, then move the address on as the cache may, before the data.
    // The first line is registered on the source's ready and the done comes
    // a clock later; the second follows a clock after that, as SDRAM's does.
    // Both inputs are then disturbed, so a combinational output would show.
    task read(input [24:0] a);
        begin
            rd_addr=a; rd_req=1; @(negedge clk); rd_req=0;
            rd_addr=a+25'd7; @(negedge clk); @(negedge clk);
            rd_ready=1; @(negedge clk); rd_ready=0;
            if (rd_ready_out!==1'b1) $fatal(1,"FAIL done was not delayed exactly one clock");
            @(negedge clk);
            if (rd_ready_out!==1'b0) $fatal(1,"FAIL done lasted more than one clock");
            din_first=~din_first; din_second=~din_second; @(negedge clk);
            din_first=~din_first; din_second=~din_second;
        end
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
        if (changes!==2) $fatal(1,"FAIL changed pulsed %0d times, expected 2", changes);
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

        // A whole table, then one too many. A ROM cheat is a run of patches,
        // not one, so the boundary is worth pinning: the last slot lands and
        // the entry after it is dropped rather than wrapping onto slot zero.
        for (n = 0; n < 16; n = n + 1)
            push(28'h8001000 + (n << 2), 32'h000000A0 + n, 4'h1, 4'd0);
        if (count!==16) $fatal(1,"FAIL full table count %0d, expected 16", count);
        read(25'h403);                          // 0x0800100C, slot 3
        if (dout_first!==32'h112233A3) $fatal(1,"FAIL slot 3 %h", dout_first);
        read(25'h40F);                          // 0x0800103C, slot 15
        if (dout_first!==32'h112233AF) $fatal(1,"FAIL slot 15 %h", dout_first);
        push(28'h8002000, 32'h000000FF, 4'h1, 4'd0);
        if (count!==16) $fatal(1,"FAIL table overran to %0d", count);
        read(25'h800);
        if (dout_first!==32'h11223344) $fatal(1,"FAIL seventeenth entry landed %h", dout_first);

        // Lowest slot wins a contested lane, and a lane the lower slot does
        // not claim still takes the higher one's byte.
        load_reset=1; @(negedge clk); load_reset=0;
        push(28'h8004000, 32'h00005500, 4'h2, 4'd0);   // slot 0: lane 1 = 55
        push(28'h8004000, 32'h00CC6600, 4'h6, 4'd0);   // slot 1: lane 1 = 66 (loses), lane 2 = CC
        if (count!==2) $fatal(1,"FAIL same DWORD took %0d slots, expected 2", count);
        read(25'h1000);
        if (dout_first!==32'h11CC5544)
            $fatal(1,"FAIL lowest slot did not win the lane: %h", dout_first);

        $display("PASS rom_patch: fill from the push, both words, byte lanes, RAM and conditional entries ignored, reset, 16 slots, no overrun, lowest slot wins, registered line and one-clock done");
        $finish;
    end
    initial begin #200000; $fatal(1,"rom_patch watchdog"); end
endmodule
