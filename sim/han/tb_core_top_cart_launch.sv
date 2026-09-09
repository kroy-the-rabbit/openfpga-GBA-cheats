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
    task expect_debug(input [31:0] status);
        integer word_index;
        reg [31:0] expected;
        begin
            for(word_index=0;word_index<4;word_index=word_index+1) begin
                case(word_index)
                    1: expected=status;
                    default: expected=0; // Retired readouts must not expose stale state.
                endcase
                @(negedge clk);bridge_addr=32'hf4000010+word_index*4;bridge_rd=1;
                @(negedge clk);
                if(bridge_rd_data!==expected)
                    $fatal(1,"FAIL top debug word%0d got%h expected%h",word_index,bridge_rd_data,expected);
                bridge_rd=0;
            end
        end
    endtask
    reg [31:0] captured_header=0, stable_header=0;
    integer header_samples=0;
    reg hreq=0, hready=0;
    reg [24:0] haddr=0;
    reg [31:0] hfirst=0, hsecond=0;
    initial begin
        force dut.sdram_read_req_gba=hreq;
        force dut.sdram_read_addr_gba=haddr;
        force dut.romsrc_gba_rd_ready=hready;
        force dut.romsrc_gba_rd_data=hfirst;
        force dut.romsrc_gba_rd_data_second=hsecond;
        force dut.cart_hdr_id=32'h424d5845;
    end
    task bad_header_read;
        begin
            @(negedge clk);haddr=5;hreq=1;
            @(negedge clk);hreq=0;haddr=0;
            repeat(3) @(negedge clk);
            hfirst=32'h12345678;hsecond=32'hdeadbeef;hready=1;
            @(negedge clk);hready=0;
            repeat(3) @(negedge clk);
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
        // Actual checker and snapshot. Supply only the external ROM bus,
        // never force checker results or CPU debug signals.
        detected=1;
        command(16'h00b1,32'h01010000);
        force dut.reset_gba=1;
        bad_header_read();
        expect_debug(0); // Not captured yet.
        command(16'h00b0,1);
        expect_debug(32'h013a14f0);
        stable_header = captured_header;
        bad_header_read();
        command(16'h00b0,1); // Already open: retain the same snapshot.
        expect_debug(stable_header);
        if (captured_header !== stable_header) $fatal(1,"FAIL recaptured while menu open");
        command(16'h00b0,0);
        command(16'h00b0,1);
        expect_debug(32'h12345678); // second open: the bad DWORD's value
        command(16'h00b0,0);
        command(16'h00b0,1);
        expect_debug(32'h023a14f0); // third open: status again
        if (header_samples != 3) $fatal(1,"FAIL header capture count %0d",header_samples);
        $display("PASS core_top cartridge launch: real APF notification, synchronization, reset/probe gating, SD-save isolation and stale-menu immunity");
        $display("PASS core_top debug packing, live header mismatch, retired addresses zero and stable APF menu snapshots during GBA reset");
        $finish;
    end
    initial begin #100000; $fatal(1,"FAIL top cartridge launch watchdog"); end
endmodule
