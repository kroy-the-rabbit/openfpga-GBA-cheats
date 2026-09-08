// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// Real core_top mode/reset/save equations and actual APF handler. Unrelated
// FPGA/VHDL engines are omitted with iverilog -i; only their environmental
// outputs needed by this control path are supplied below.
module tb_core_top_cart_launch;
    reg clk=0;
    always #5 clk=~clk;
    reg [31:0] bridge_addr=0,bridge_wr_data=0;
    reg bridge_wr=0,bridge_rd=0;
    wire [31:0] bridge_rd_data;
    reg detected=0;
    core_top dut(.clk_74a(clk),.clk_74b(clk),.bridge_addr(bridge_addr),
        .bridge_wr(bridge_wr),.bridge_wr_data(bridge_wr_data),
        .bridge_rd(bridge_rd),.bridge_rd_data(bridge_rd_data));
    initial begin
        dut.icb.hstate=0;dut.icb.tstate=0;dut.icb.host_cmd_start=0;
        force dut.clk_sys=clk;
        force dut.pll_core_locked=1;
        force dut.other_slot_downloading_s=0;
        force dut.core_reset_s=0;
        force dut.save_mem_ready=1;
        force dut.flash_1m_s=0;
        force dut.rtc_active=0;
        force dut.cart_detect=detected;
    end
    task write_word(input [31:0] addr,input [31:0] data);
        begin
            @(negedge clk);bridge_addr=addr;bridge_wr_data=data;bridge_wr=1;
            @(negedge clk);bridge_wr=0;
        end
    endtask
    task command(input [15:0] opcode,input [31:0] arg);
        integer timeout;
        reg [31:0] response;
        begin
            write_word(32'hf8000020,arg);
            write_word(32'hf8000000,{16'h434d,opcode});
            timeout=0;response=0;
            while(response[31:16]!==16'h4f4b && timeout<100) begin
                @(negedge clk);bridge_addr=32'hf8000000;bridge_rd=1;
                @(negedge clk);response=bridge_rd_data;bridge_rd=0;timeout=timeout+1;
            end
            if(response!==32'h4f4b0000) $fatal(1,"FAIL top APF command %h response %h",opcode,response);
            repeat(8) @(negedge clk);
        end
    endtask
    task expect_mode(input selected,input powered,input rom,input held_reset,input saves);
        begin
            if({dut.cart_rom_select_s,dut.cart_hw_enable_s,dut.cart_rom_mode,dut.reset_gba,dut.savestate_supported}
                !== {selected,powered,rom,held_reset,saves})
                $fatal(1,"FAIL top cartridge mode selected=%b powered=%b rom=%b reset=%b savestates=%b",
                    dut.cart_rom_select_s,dut.cart_hw_enable_s,dut.cart_rom_mode,dut.reset_gba,dut.savestate_supported);
            if(dut.save_size_bytes !== (saves ? 32'h10000 : 32'd0))
                $fatal(1,"FAIL top SD-save size %h",dut.save_size_bytes);
        end
    endtask
    initial begin
        repeat(10) @(negedge clk);
        command(16'h0011,0);
        expect_mode(0,0,0,0,1);
        // A previously persisted manual Boot setting cannot override SD mode.
        write_word(32'h90,2);repeat(8) @(negedge clk);
        expect_mode(0,0,0,0,1);
        command(16'h00b1,32'h01010000);
        expect_mode(1,1,0,1,0); // probe has not identified a cartridge yet
        command(16'h0010,0);expect_mode(1,1,0,1,0);
        if(dut.cart_ctl_reset_n!==0) $fatal(1,"FAIL cartridge controller released during Reset Enter");
        command(16'h0011,0);expect_mode(1,1,0,1,0);
        if(dut.cart_ctl_reset_n!==1) $fatal(1,"FAIL cartridge controller held after Reset Exit");
        detected=1;repeat(8) @(negedge clk);
        expect_mode(1,1,1,0,0); // success enables ROM and physical save route
        command(16'h00b1,32'h01000000);
        expect_mode(1,0,0,1,0); // lost cartridge power holds CPU even if ID is stale
        command(16'h00b1,32'h01010000);expect_mode(1,1,1,0,0);
        detected=0;repeat(8) @(negedge clk);
        expect_mode(1,1,0,1,0); // failed probe must not run stale SDRAM game
        command(16'h00b1,32'h00010000);expect_mode(0,0,0,0,1);
        command(16'h00b1,0);expect_mode(0,0,0,0,1);
        $display("PASS core_top cartridge launch: real APF notification, synchronization, reset/probe gating, SD-save isolation and stale-menu immunity");
        $finish;
    end
    initial begin #100000; $fatal(1,"FAIL top cartridge launch watchdog"); end
endmodule
