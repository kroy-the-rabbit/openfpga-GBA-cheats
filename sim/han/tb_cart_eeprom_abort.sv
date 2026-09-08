// SPDX-License-Identifier: GPL-3.0-or-later
// DMA lifetime regression. The controller drains every accepted bit; no
// serial-chip reset behavior is assumed or used to recover an abort.
`timescale 1ns/1ps
module eeprom_abort_case #(parameter CASE_ID=0)(output reg finished=0);
    reg clk=0, reset_n=0, write_enable=0;
    always #5 clk=~clk;
    reg host_req=0, host_rnw=0, host_din=0, host_dma=1, host_last=0;
    reg host_dma_active=1;
    reg [16:0] host_count=81;
    wire host_dout, host_done, fault;
    wire ctl_req, ctl_rnw, ctl_din, ctl_dma;
    reg ctl_done=0;
    wire ctl_dout=1;
    cart_eeprom_bridge dut (.*);
    integer accepted=0, completed=0, pending=0;
    always @(posedge clk) begin
        ctl_done<=0;
        if (ctl_req) begin
            if (pending!=0) $fatal(1,"case%0d controller request collision",CASE_ID);
            pending=5;
            accepted=accepted+1;
        end else if (pending>0) begin
            pending=pending-1;
            if (pending==0) begin ctl_done<=1;completed=completed+1;end
        end
    end
    task launch(input bit value, input bit last_bit);
        begin
            @(negedge clk);host_din=value;host_last=last_bit;host_req=1;
            @(negedge clk);host_req=0;
        end
    endtask
    task retire;
        integer timeout;
        begin
            timeout=0;
            while (!host_done && timeout<100) begin
                @(negedge clk);timeout=timeout+1;
            end
            if (!host_done) $fatal(1,"case%0d host request timeout",CASE_ID);
            @(negedge clk);
        end
    endtask
    task bit_access(input bit value, input bit last_bit);
        begin launch(value,last_bit);retire();end
    endtask
    task reject_after_fault;
        integer previous;
        begin
            previous=accepted;
            host_dma_active=1;write_enable=0;host_count=73;
            bit_access(1,0);bit_access(0,0);
            write_enable=1;bit_access(1,0);
            host_rnw=1;host_dma=0;bit_access(0,1);
            if (host_dout!==1 || accepted!=previous || fault!==1)
                $fatal(1,"case%0d fault did not block subsequent traffic",CASE_ID);
            @(negedge clk);reset_n=0;
            repeat(4) @(negedge clk);reset_n=1;
            host_rnw=0;host_dma=1;write_enable=1;bit_access(1,0);
            if (fault!==1 || accepted!=previous)
                $fatal(1,"case%0d soft reset cleared fault or forwarded traffic",CASE_ID);
        end
    endtask
    integer i;
    initial begin
        repeat(4) @(negedge clk);reset_n=1;
        case (CASE_ID)
            0: begin
                // A locally buffered prefix or denied program never touched
                // the chip: abort clears policy without latching a fault.
                host_count=17;bit_access(1,0);host_dma_active=0;
                repeat(4) @(negedge clk);
                if (fault!==0 || accepted!=0) $fatal(1,"buffered abort faulted");
                host_dma_active=1;host_count=9;
                for(i=0;i<9;i=i+1) bit_access(i<2,i==8);
                host_dma_active=0;repeat(4) @(negedge clk);
                if (fault!==0 || accepted!=9) $fatal(1,"fresh read after buffered abort failed");
                host_dma_active=1;host_count=81;
                bit_access(1,0);bit_access(0,0);host_dma_active=0;
                repeat(4) @(negedge clk);
                host_dma_active=1;write_enable=1;
                for(i=0;i<81;i=i+1) bit_access(i==0,i==80);
                if (fault!==0 || accepted!=90) $fatal(1,"denied abort retained old policy");
            end
            1: begin
                // Original bug: aborted enabled command authorized a later
                // disabled DMA, even when its transfer count was different.
                write_enable=1;bit_access(1,0);bit_access(0,0);
                host_dma_active=0;write_enable=0;repeat(4) @(negedge clk);
                if (fault!==1) $fatal(1,"physical abort did not latch fault");
                reject_after_fault();
            end
            2: begin
                // Preemption leaves DMA3 active. Permission stays fixed until
                // the final bit; final completion and DMA drop may coincide.
                write_enable=1;bit_access(1,0);bit_access(0,0);write_enable=0;
                repeat(150) @(negedge clk);
                for(i=2;i<80;i=i+1) bit_access(0,0);
                launch(0,1);wait(host_done);host_dma_active=0;
                repeat(4) @(negedge clk);
                if (fault!==0 || accepted!=81 || completed!=81)
                    $fatal(1,"normal last completion plus DMA drop faulted");
            end
            3,4: begin
                // Abort while physically pending. CASE4 interrupts prefix
                // replay: bit1 drains and bit2 must never be launched.
                write_enable=(CASE_ID==3);
                if(CASE_ID==4) begin host_count=17;bit_access(1,0);end
                launch(1,0);wait(accepted==1);
                @(negedge clk);host_dma_active=0;retire();
                if (fault!==1 || accepted!=1 || completed!=1)
                    $fatal(1,"case%0d failed to drain exactly one accepted bit",CASE_ID);
                reject_after_fault();
            end
            5: begin
                // Soft reset itself must capture the physical parser hazard.
                write_enable=1;bit_access(1,0);bit_access(0,0);
                @(negedge clk);reset_n=0;
                repeat(4) @(negedge clk);reset_n=1;
                if (fault!==1) $fatal(1,"soft reset of partial command did not fault");
                reject_after_fault();
            end
            6: begin
                // A new host request may arrive on the clock retiring the
                // previous final completion. It must open a fresh monitor.
                write_enable=1;host_rnw=1;host_count=1;
                launch(0,1);wait(host_done);
                @(negedge clk);host_req=1;host_rnw=0;host_din=1;host_last=0;host_count=81;
                @(negedge clk);host_req=0;retire();
                host_dma_active=0;repeat(4) @(negedge clk);
                if (fault!==1) $fatal(1,"back-to-back new transfer was not monitored");
                reject_after_fault();
            end
        endcase
        $display("PASS: EEPROM DMA boundary/fault case %0d",CASE_ID);
        finished=1;
    end
endmodule
module tb_cart_eeprom_abort;
    wire [6:0] finished;
    genvar i;
    generate for(i=0;i<7;i=i+1) begin: cases
        eeprom_abort_case #(.CASE_ID(i)) test_case(finished[i]);
    end endgenerate
    initial begin wait(&finished);$finish;end
    initial begin #1000000;$fatal(1,"abort bench watchdog");end
endmodule
