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
    task expect_debug(input [31:0] pc,input [31:0] status);
        integer word_index;
        reg [31:0] expected;
        begin
            for(word_index=0;word_index<4;word_index=word_index+1) begin
                case(word_index)
                    0: expected=pc;
                    1: expected=status;
                    2: expected=0; // Retired readout must not expose stale state.
                    3: expected=0;
                endcase
                @(negedge clk);bridge_addr=32'hf4000010+word_index*4;bridge_rd=1;
                @(negedge clk);
                if(bridge_rd_data!==expected)
                    $fatal(1,"FAIL top debug word%0d got%h expected%h",word_index,bridge_rd_data,expected);
                bridge_rd=0;
            end
        end
    endtask
    reg [63:0] captured_pattern=0, stable_pattern=0;
    reg [63:0] expected_pattern=64'hD1A65EED4B3C2907;
    integer pattern_samples=0;
    always @(posedge clk) begin
        if (dut.cart_debug_pattern !== expected_pattern)
            $fatal(1,"FAIL diagnostic pattern sequence");
        expected_pattern = {expected_pattern[62:0],expected_pattern[63]};
        if (dut.boot_debug.request_sync[1] != dut.boot_debug.ack_toggle) begin
            captured_pattern = dut.cart_debug_pattern;
            pattern_samples = pattern_samples + 1;
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
        // Actual free-running pattern and actual snapshot, with no forced
        // diagnostic payload or CPU debug outputs. Capture during GBA reset.
        force dut.reset_gba=1;
        expect_debug(0,0);
        command(16'h00b0,1);
        expect_debug(captured_pattern[31:0],captured_pattern[63:32]);
        stable_pattern = captured_pattern;
        command(16'h00b0,1); // Already open: retain the same snapshot.
        expect_debug(stable_pattern[31:0],stable_pattern[63:32]);
        if (captured_pattern !== stable_pattern) $fatal(1,"FAIL pattern recaptured while menu open");
        command(16'h00b0,0);
        command(16'h00b0,1);
        expect_debug(captured_pattern[31:0],captured_pattern[63:32]);
        if (pattern_samples != 2) $fatal(1,"FAIL pattern capture count %0d",pattern_samples);
        $display("PASS core_top cartridge launch: real APF notification, synchronization, reset/probe gating, SD-save isolation and stale-menu immunity");
        $display("PASS core_top debug packing, dynamic pattern, retired addresses zero and stable APF menu snapshots during GBA reset");
        $finish;
    end
    initial begin #100000; $fatal(1,"FAIL top cartridge launch watchdog"); end
endmodule
