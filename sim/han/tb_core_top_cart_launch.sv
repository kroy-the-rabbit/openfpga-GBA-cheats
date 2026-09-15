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
    reg io_req=0, rom_req=0;
    reg [31:0] cpu_pc=32'h08040000;
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
        force dut.cart_io_req=io_req;
        force dut.cart_io_addr=24'hfc00a0;
        force dut.cart_io_rnw=0;
        force dut.cart_io_wdata=16'h1234;
        force dut.romsrc_cart_rd_req=rom_req;
        force dut.gba_debug_pc=cpu_pc;
        force dut.gba_debug_mixed=32'd1;
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
            if({dut.cart_rom_select_s,dut.cart_hw_enable_s,dut.cart_rom_mode,dut.reset_gba}
                !== {selected,powered,rom,held_reset})
                $fatal(1,"FAIL top cartridge mode selected=%b powered=%b rom=%b reset=%b",
                    dut.cart_rom_select_s,dut.cart_hw_enable_s,dut.cart_rom_mode,dut.reset_gba);
            // Savestates are removed; the APF flag must never come back on.
            if(dut.savestate_supported !== 1'b0)
                $fatal(1,"FAIL top savestate_supported asserted");
            if(dut.save_size_bytes !== (saves ? 32'h10000 : 32'd0))
                $fatal(1,"FAIL top SD-save size %h",dut.save_size_bytes);
        end
    endtask
    task expect_debug(input [63:0] status);
        integer word_index;
        reg [31:0] expected, address;
        begin
            for(word_index=0;word_index<5;word_index=word_index+1) begin
                case(word_index)
                    0: begin expected=status[63:32]; address=32'hf4000008; end
                    1: begin expected=status[31:0]; address=32'hf4000014; end
                    2: begin expected=0; address=32'hf4000010; end
                    3: begin expected=0; address=32'hf4000018; end
                    4: begin expected=0; address=32'hf400001c; end
                endcase
                @(negedge clk);bridge_addr=address;bridge_rd=1;
                @(negedge clk);
                if(bridge_rd_data!==expected)
                    $fatal(1,"FAIL top debug word%0d got%h expected%h",word_index,bridge_rd_data,expected);
                bridge_rd=0;
            end
        end
    endtask
    reg [63:0] captured_header=0, stable_header=0;
    integer header_samples=0;
    // Drive the omitted CPU's bus outputs. The real top packs the flash-cart
    // access and CPU position into the two diagnostic words.
    task flashcart_write;
        begin
            @(negedge clk);io_req=1;
            @(negedge clk);io_req=0;rom_req=1;
            repeat(3) @(negedge clk);
            rom_req=0;
            repeat(6) @(negedge clk);
        end
    endtask
    always @(posedge clk) begin
        if (dut.boot_debug.request_sync[1] != dut.boot_debug.ack_toggle) begin
            captured_header = dut.boot_debug.sys_debug;
            header_samples = header_samples + 1;
        end
    end
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
        // Actual flash-cart counters, packing and snapshot. Supply the bus
        // outputs of the omitted CPU and memory subsystem.
        detected=1;
        command(16'h00b1,32'h01010000);
        force dut.reset_gba=1;
        flashcart_write();
        expect_debug(0); // Not captured yet.
        command(16'h00b0,1);
        expect_debug(64'h12340304_8818fca0);
        stable_header = captured_header;
        cpu_pc=32'h02050000;
        command(16'h00b0,1); // Already open: retain the same snapshot.
        expect_debug(stable_header);
        if (captured_header !== stable_header) $fatal(1,"FAIL recaptured while menu open");
        command(16'h00b0,0);
        command(16'h00b0,1);
        expect_debug(64'h12340305_2818fca0); // reopened: current CPU position
        if (header_samples != 2) $fatal(1,"FAIL capture count %0d",header_samples);
        $display("PASS core_top cartridge launch: real APF notification, synchronization, reset/probe gating, SD-save isolation and stale-menu immunity");
        $display("PASS core_top debug packing, flash-cart access and CPU position, retired addresses zero and stable APF menu snapshots during GBA reset");
        $finish;
    end
    initial begin #100000; $fatal(1,"FAIL top cartridge launch watchdog"); end
endmodule
