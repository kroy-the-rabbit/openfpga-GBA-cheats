// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// Exercise actual APF command/status bus transactions, including byte order.
module tb_core_bridge_cart_notify;
    reg clk=0;
    always #5 clk=~clk;
    reg bridge_endian_little=0,bridge_wr=0,bridge_rd=0;
    reg [31:0] bridge_addr=0,bridge_wr_data=0;
    wire [31:0] bridge_rd_data;
    wire reset_n,osnotify_cart_play,osnotify_cart_power,osnotify_inmenu;
    reg savestate_supported=0,savestate_start_ack=0,savestate_load_ack=0;
    wire savestate_start,savestate_load;
    integer start_cycles=0,load_cycles=0;
    always @(posedge clk) begin
        if(savestate_start) start_cycles=start_cycles+1;
        if(savestate_load) load_cycles=load_cycles+1;
    end
    core_bridge_cmd dut (
        .clk(clk), .reset_n(reset_n),
        .bridge_endian_little(bridge_endian_little), .bridge_wr(bridge_wr),
        .bridge_rd(bridge_rd), .bridge_addr(bridge_addr),
        .bridge_wr_data(bridge_wr_data), .bridge_rd_data(bridge_rd_data),
        .osnotify_cart_play(osnotify_cart_play), .osnotify_cart_power(osnotify_cart_power),
        .osnotify_inmenu(osnotify_inmenu),
        .status_boot_done(1'b1), .status_setup_done(1'b0), .status_running(1'b0),
        .dataslot_requestread_ack(1'b1), .dataslot_requestread_ok(1'b1),
        .dataslot_requestwrite_ack(1'b1), .dataslot_requestwrite_ok(1'b1),
        .savestate_supported(savestate_supported), .savestate_addr(32'b0), .savestate_size(32'b0),
        .savestate_maxloadsize(32'b0), .savestate_start_ack(savestate_start_ack), .savestate_start(savestate_start),
        .savestate_start_busy(1'b0), .savestate_start_ok(1'b0), .savestate_start_err(1'b0),
        .savestate_load_ack(savestate_load_ack), .savestate_load(savestate_load), .savestate_load_busy(1'b0), .savestate_load_ok(1'b0), .savestate_load_err(1'b0),
        .target_dataslot_read(1'b0), .target_dataslot_write(1'b0),
        .target_dataslot_getfile(1'b0), .target_dataslot_openfile(1'b0),
        .target_dataslot_id(16'b0), .target_dataslot_slotoffset(32'b0),
        .target_dataslot_bridgeaddr(32'b0), .target_dataslot_length(32'b0),
        .target_buffer_param_struct(32'b0), .target_buffer_resp_struct(32'b0),
        .datatable_addr(10'b0), .datatable_wren(1'b0), .datatable_data(32'b0)
    );
    // The APF template relies on Quartus zero-power-up for these FSM regs;
    // initialize only that existing implicit state, never the new outputs.
    initial begin dut.hstate=0;dut.tstate=0;dut.host_cmd_start=0;end
    function [31:0] wire_order(input [31:0] data);
        wire_order=bridge_endian_little ? {data[7:0],data[15:8],data[23:16],data[31:24]} : data;
    endfunction
    task write_word(input [31:0] addr,input [31:0] data);
        begin
            @(negedge clk);bridge_addr=addr;bridge_wr_data=wire_order(data);bridge_wr=1;
            @(negedge clk);bridge_wr=0;
        end
    endtask
    task read_status(output [31:0] data);
        begin
            @(negedge clk);bridge_addr=32'hf8000000;bridge_rd=1;
            @(negedge clk);data=wire_order(bridge_rd_data);bridge_rd=0;
        end
    endtask
    integer commands=0;
    task command_result(input [15:0] opcode,input [31:0] arg,input [15:0] expected_result);
        integer timeout;
        reg [31:0] response;
        begin
            write_word(32'hf8000020,arg);
            write_word(32'hf8000000,{16'h434d,opcode});
            timeout=0;response=0;
            while(response[31:16]!==16'h4f4b && timeout<100) begin
                read_status(response);timeout=timeout+1;
            end
            if(response!=={16'h4f4b,expected_result})
                $fatal(1,"FAIL APF command %h response %h endian=%b",opcode,response,bridge_endian_little);
            commands=commands+1;
        end
    endtask
    task command(input [15:0] opcode,input [31:0] arg);
        command_result(opcode,arg,16'b0);
    endtask
    task expect_notify(input play,input power);
        begin
            if({osnotify_cart_play,osnotify_cart_power} !== {play,power})
                $fatal(1,"FAIL APF cart notify got play=%b power=%b expected %b %b",
                    osnotify_cart_play,osnotify_cart_power,play,power);
        end
    endtask
    integer endian_mode;
    initial begin
        repeat(8) @(negedge clk);
        expect_notify(0,0);
        for(endian_mode=0;endian_mode<2;endian_mode=endian_mode+1) begin
            bridge_endian_little=endian_mode;
            repeat(8) @(negedge clk);
            command(16'h00b1,32'h01010000);expect_notify(1,1);
            command(16'h0010,0);expect_notify(1,1);
            if(reset_n!==0) $fatal(1,"FAIL reset enter");
            command(16'h008f,0);expect_notify(1,1);
            command(16'h0011,0);expect_notify(1,1);
            if(reset_n!==1) $fatal(1,"FAIL reset exit");
            command(16'h00b0,1);expect_notify(1,1);
            if(osnotify_inmenu!==1) $fatal(1,"FAIL menu notify regression");
            command(16'h00b1,32'h01000000);expect_notify(1,0);
            command(16'h0010,0);expect_notify(1,0);
            command(16'h0011,0);expect_notify(1,0);
            command(16'h00b1,32'h00010000);expect_notify(0,1);
            command(16'h00b1,32'h00000000);expect_notify(0,0);
            command(16'h00b1,32'hfefeffff);expect_notify(0,0);
            command(16'h0010,0);expect_notify(0,0);
            command(16'h0011,0);expect_notify(0,0);
        end
        // Cartridge mode disables savestates. Rejected save/load requests
        // must finish without waiting for an ack and never reach user logic.
        command_result(16'h00a0,1,16'd3);
        command_result(16'h00a4,1,16'd3);
        if(start_cycles!=0 || load_cycles!=0)
            $fatal(1,"FAIL unsupported savestate request emitted start/load pulse");
        // Ordinary SD-ROM mode retains the existing delayed-ack handshake.
        savestate_supported=1;
        fork
            command(16'h00a0,1);
            begin
                wait(savestate_start);
                repeat(3) begin @(negedge clk);
                    if(!savestate_start) $fatal(1,"FAIL save request dropped before ack");
                end
                savestate_start_ack=1;
                @(negedge clk);savestate_start_ack=0;
            end
        join
        fork
            command(16'h00a4,1);
            begin
                wait(savestate_load);
                repeat(3) begin @(negedge clk);
                    if(!savestate_load) $fatal(1,"FAIL load request dropped before ack");
                end
                savestate_load_ack=1;
                @(negedge clk);savestate_load_ack=0;
            end
        join
        if(start_cycles<3 || load_cycles<3)
            $fatal(1,"FAIL supported savestate handshake did not run");
        $display("PASS APF savestate commands: unsupported requests complete without pulses, supported requests wait for ack");
        $display("PASS APF cartridge notification: %0d commands, both byte orders, play/power updates and reset retention",commands);
        $finish;
    end
    initial begin #100000; $fatal(1,"FAIL APF cart notify watchdog"); end
endmodule

// The command tests never address the data table. Its block-RAM primitive
// is replaced with a conventional synchronous dual-port model for Icarus.
module mf_datatable(
    input [9:0] address_a,address_b,
    input clock_a,clock_b,
    input [31:0] data_a,data_b,
    input wren_a,wren_b,
    output reg [31:0] q_a,q_b
);
    reg [31:0] mem[0:1023];
    always @(posedge clock_a) begin
        if(wren_a) mem[address_a]<=data_a;
        q_a<=mem[address_a];
    end
    always @(posedge clock_b) begin
        if(wren_b) mem[address_b]<=data_b;
        q_b<=mem[address_b];
    end
endmodule

// The APF RTL instantiates synch_3 with three positional ports, omitting
// common.v's optional rise/fall outputs. Icarus rejects omitted positional
// ports, so use the same three-stage data synchronizer with those ports absent.
module synch_3 #(parameter WIDTH=1)(input [WIDTH-1:0] i,output reg [WIDTH-1:0] o,input clk);
    reg [WIDTH-1:0] stage_1,stage_2;
    always @(posedge clk) {o,stage_2,stage_1}<={stage_2,stage_1,i};
endmodule
