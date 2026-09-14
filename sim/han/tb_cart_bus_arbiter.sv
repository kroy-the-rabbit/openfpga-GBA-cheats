// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
module tb_cart_bus_arbiter;
    reg clk=0,reset_n=0;
    always #5 clk=~clk;
    reg probe_req=0,rom_req=0,save_req=0,ee_req=0;
    reg [24:0] probe_addr=25'h123,rom_addr=25'h456;
    reg [16:0] save_addr=17'h153ac;
    reg save_rnw=0,ee_rnw=0,ee_din=1,ee_dma=1;
    reg [7:0] save_din=8'hb7;
    reg io_req=0,io_rnw=0;
    reg [23:0] io_addr=24'h4ff000;
    reg [15:0] io_din=16'hd200;
    wire io_done,ctl_io_req,ctl_io_rnw;
    wire [23:0] ctl_io_addr;
    wire [15:0] ctl_io_din;
    reg ctl_io_done=0;
    integer io_transactions=0,io_responses=0;
    reg [40:0] held_io;
    wire probe_done,rom_done,save_done,ee_done,busy;
    wire ctl_rom_req,ctl_save_req,ctl_ee_req;
    wire [24:0] ctl_rom_addr;
    wire [16:0] ctl_save_addr;
    wire [7:0] ctl_save_din;
    wire ctl_save_rnw,ctl_ee_rnw,ctl_ee_din,ctl_ee_dma;
    reg ctl_rom_done=0,ctl_save_done=0,ctl_ee_done=0;
    cart_bus_arbiter dut (.*);
    integer timer=0,owner=0;
    integer rom_transactions=0,save_transactions=0,ee_transactions=0;
    integer probe_responses=0,rom_responses=0,save_responses=0,ee_responses=0;
    reg [24:0] held_rom_addr;
    reg [25:0] held_save;
    reg [2:0] held_ee;
    always @(posedge clk) if(reset_n) begin
        if(probe_done) probe_responses=probe_responses+1;
        if(rom_done) rom_responses=rom_responses+1;
        if(save_done) save_responses=save_responses+1;
        if(ee_done) ee_responses=ee_responses+1;
        if(io_done) io_responses=io_responses+1;
        if(ctl_io_done && owner!=4 && io_done)
            $fatal(1,"FAIL: unrelated IO completion escaped");
        if((probe_done+rom_done+save_done+ee_done+io_done)>1)
            $fatal(1,"FAIL: completion delivered to multiple clients");
        if(ctl_rom_done && owner!=1 && (probe_done || rom_done))
            $fatal(1,"FAIL: unrelated ROM completion escaped");
        if(ctl_save_done && owner!=2 && save_done)
            $fatal(1,"FAIL: unrelated SRAM completion escaped");
        if(ctl_ee_done && owner!=3 && ee_done)
            $fatal(1,"FAIL: unrelated EEPROM completion escaped");
        ctl_rom_done<=0;ctl_save_done<=0;ctl_ee_done<=0;ctl_io_done<=0;
        if(ctl_rom_req || ctl_save_req || ctl_ee_req || ctl_io_req) begin
            if(timer!=0 || (ctl_rom_req+ctl_save_req+ctl_ee_req+ctl_io_req)!=1)
                $fatal(1,"FAIL: controller request collision");
            timer=12;
            if(ctl_rom_req) begin
                owner=1;
                if(ctl_rom_addr !== ((rom_transactions==0)?25'h123:25'h456))
                    $fatal(1,"FAIL: queued ROM payload corrupted");
                held_rom_addr=ctl_rom_addr;
                rom_transactions=rom_transactions+1;
            end else if(ctl_save_req) begin
                owner=2;
                if({ctl_save_addr,ctl_save_rnw,ctl_save_din} !== {17'h153ac,1'b0,8'hb7})
                    $fatal(1,"FAIL: queued save payload corrupted");
                held_save={ctl_save_addr,ctl_save_rnw,ctl_save_din};
                save_transactions=save_transactions+1;
            end else if(ctl_io_req) begin
                owner=4;
                if({ctl_io_rnw,ctl_io_addr,ctl_io_din} !== {1'b0,24'h4ff000,16'hd200})
                    $fatal(1,"FAIL: queued IO payload corrupted");
                held_io={ctl_io_rnw,ctl_io_addr,ctl_io_din};
                io_transactions=io_transactions+1;
            end else begin
                owner=3;
                if({ctl_ee_rnw,ctl_ee_din,ctl_ee_dma} !== 3'b011)
                    $fatal(1,"FAIL: queued EEPROM payload corrupted");
                held_ee={ctl_ee_rnw,ctl_ee_din,ctl_ee_dma};
                ee_transactions=ee_transactions+1;
            end
        end else if(timer!=0) begin
            if(owner==1 && ctl_rom_addr !== held_rom_addr) $fatal(1,"FAIL: active ROM payload changed");
            if(owner==2 && {ctl_save_addr,ctl_save_rnw,ctl_save_din} !== held_save) $fatal(1,"FAIL: active save payload changed");
            if(owner==3 && {ctl_ee_rnw,ctl_ee_din,ctl_ee_dma} !== held_ee) $fatal(1,"FAIL: active EEPROM payload changed");
            if(owner==4 && {ctl_io_rnw,ctl_io_addr,ctl_io_din} !== held_io) $fatal(1,"FAIL: active IO payload changed");
            timer=timer-1;
            if(timer==0) begin
                // The real controller historically pulses multiple done
                // outputs together. Only the owner may receive completion.
                ctl_rom_done<=1;ctl_save_done<=1;ctl_ee_done<=1;ctl_io_done<=1;
            end
        end
    end
    initial begin
        repeat(5) @(negedge clk);reset_n=1;
        @(negedge clk);probe_req=1;
        wait(probe_done);repeat(30) @(negedge clk);
        if(rom_transactions!=1 || probe_responses!=1 || rom_responses!=0)
            $fatal(1,"FAIL: held probe generated duplicate transaction or wrong completion");
        probe_req=0;
        repeat(3) @(negedge clk);
        rom_req=1;
        @(negedge clk);rom_req=0;rom_addr=0;
        wait(ctl_rom_req);@(negedge clk);
        save_req=1;ee_req=1;io_req=1;
        @(negedge clk);save_req=0;ee_req=0;io_req=0;
        save_addr=0;save_din=0;save_rnw=1;ee_rnw=1;ee_din=0;ee_dma=0;
        io_addr=0;io_din=0;io_rnw=1;
        wait(save_responses==1 && ee_responses==1 && rom_responses==1 && io_responses==1);
        repeat(15) @(negedge clk);
        if(busy || rom_transactions!=2 || save_transactions!=1 || ee_transactions!=1 ||
           io_transactions!=1 || probe_responses!=1)
            $fatal(1,"FAIL: queued requests lost, repeated, or did not drain");
        $display("PASS: arbiter pulse capture, payload latching, typed completion, held probe, IO client and queue draining");
        $finish;
    end
    initial begin #100000; $fatal(1,"FAIL: arbiter watchdog"); end
endmodule
