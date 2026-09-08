// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// Actual core_top write policy -> arbiter -> controller -> pin-level ROM and
// 32KiB SRAM. Only unrelated VHDL/vendor engines are omitted by Icarus -i.
module tb_cart_sram_integration;
    reg clk=0,reset_n=0,observe=0,writes_enabled=0;
    always #5 clk=~clk;
    reg save_req=0,save_rnw=1,rom_req=0;
    reg [16:0] save_addr=0;
    reg [7:0] save_din=0;
    reg [24:0] rom_addr=0;
    wire [7:0] bank1,bank2,bank3;
    wire [7:4] bank0;
    wire dir1,dir2,dir3,pin30;
    core_top top (
        .clk_74a(clk),.clk_74b(clk),.bridge_addr(32'b0),.bridge_wr(1'b0),
        .bridge_wr_data(32'b0),.bridge_rd(1'b0),
        .cart_tran_bank1(bank1),.cart_tran_bank2(bank2),.cart_tran_bank3(bank3),
        .cart_tran_bank0(bank0),.cart_tran_pin30(pin30),
        .cart_tran_bank1_dir(dir1),.cart_tran_bank2_dir(dir2),.cart_tran_bank3_dir(dir3)
    );
    initial begin
        force top.clk_sys=clk;
        force top.cart_ctl_reset_n=reset_n;
        force top.cart_hw_enable_s=1;
        force top.cart_rom_mode=1;
        force top.cart_writes_s=writes_enabled;
        force top.cprobe_req=0;
        force top.ee_bridge_req=0;
        force top.cart_cfg_s=0;
        force top.romsrc_cart_rd_req=rom_req;
        force top.romsrc_cart_rd_addr=rom_addr;
        force top.cart_save_req=save_req;
        force top.cart_save_addr=save_addr;
        force top.cart_save_rnw=save_rnw;
        force top.cart_save_din=save_din;
    end

    reg [7:0] sram[0:32767];
    reg [15:0] sram_addr;
    reg [23:0] rom_halfaddr=0;
    integer physical_writes=0,physical_reads=0,rom_reads=0,host_reads=0,host_writes=0,denied_writes=0;
    function [7:0] seed_byte(input integer addr);
        seed_byte=(addr*73) ^ (addr>>8) ^ 8'hb6;
    endfunction
    function [15:0] rom_word(input [23:0] addr);
        rom_word=(addr[15:0]*16'h9e37) ^ {8'b0,addr[23:16]} ^ 16'hc0de;
    endfunction
    function [31:0] rom_dword(input [24:0] addr);
        reg [23:0] hw;
        begin hw=addr<<1;rom_dword={rom_word(hw+24'd1),rom_word(hw)};end
    endfunction
    integer j;
    initial for(j=0;j<32768;j=j+1) sram[j]=seed_byte(j);
    wire cs1=bank0[4],rd_n=bank0[5],wr_n=bank0[6];
    wire [15:0] rom_data=rom_word(rom_halfaddr);
    assign bank2=(observe && !cs1 && !rd_n) ? rom_data[15:8] : 8'hzz;
    assign bank3=(observe && !cs1 && !rd_n) ? rom_data[7:0] : 8'hzz;
    assign bank1=(observe && !pin30 && cs1 && !rd_n) ? sram[sram_addr[14:0]] : 8'hzz;
    always @(negedge cs1) if(observe) begin
        #1;
        if(pin30!==1 || dir2!==1 || dir3!==1 || (^{bank1,bank2,bank3})===1'bx)
            $fatal(1,"FAIL ROM address/select setup after save handoff");
        rom_halfaddr={bank1,bank2,bank3};
    end
    always @(posedge rd_n) if(observe && !cs1) rom_halfaddr[15:0]=rom_halfaddr[15:0]+1'b1;
    always @(negedge pin30) if(observe) begin
        if(cs1!==1 || rd_n!==1 || wr_n!==1 || dir2!==1 || dir3!==1 || (^{bank2,bank3})===1'bx)
            $fatal(1,"FAIL SRAM address/select setup after ROM handoff");
        sram_addr={bank2,bank3};
    end
    always @(negedge rd_n) if(observe && !pin30) physical_reads=physical_reads+1;
    always @(posedge wr_n) if(observe && !pin30) begin
        if(cs1!==1 || dir1!==1 || (^bank1)===1'bx || {bank2,bank3}!==sram_addr)
            $fatal(1,"FAIL SRAM write data/address/CS contention");
        sram[sram_addr[14:0]]=bank1;
        physical_writes=physical_writes+1;
    end
    always @(negedge clk) if(observe) begin
        if(!pin30 && !cs1) $fatal(1,"FAIL ROM and SRAM selected simultaneously");
        if(!pin30 && {bank2,bank3}!==sram_addr) $fatal(1,"FAIL SRAM address changed while selected");
        if(!rd_n && !pin30 && dir1!==0) $fatal(1,"FAIL SRAM read bus contention");
        if(top.cart_rom_ready && top.arb_save_done) $fatal(1,"FAIL controller done delivered to both clients");
    end

    task automatic byte_access(input rnw,input [16:0] addr,input [7:0] value,output [7:0] result);
        integer timeout;
        begin
            @(negedge clk);save_req=1;save_rnw=rnw;save_addr=addr;save_din=value;
            @(negedge clk);save_req=0;
            // Upstream pulse payload is no longer valid while queued.
            save_addr=~addr;save_rnw=~rnw;save_din=~value;
            timeout=0;
            while(!top.cart_save_done && timeout<2000) begin @(negedge clk);timeout=timeout+1;end
            if(!top.cart_save_done) $fatal(1,"FAIL SRAM request timeout at %h",addr);
            result=top.cart_save_dout;
            if(rnw) host_reads=host_reads+1;
            else if(writes_enabled) host_writes=host_writes+1;
            else denied_writes=denied_writes+1;
            @(negedge clk);
        end
    endtask
    task automatic check_byte(input [16:0] addr,input [7:0] expected);
        reg [7:0] value;
        begin
            byte_access(1,addr,0,value);
            if(value!==expected) $fatal(1,"FAIL SRAM read %h got %h expected %h",addr,value,expected);
        end
    endtask
    task automatic read_rom(input [24:0] addr);
        integer timeout;
        begin
            @(negedge clk);rom_addr=addr;rom_req=1;
            @(negedge clk);rom_req=0;rom_addr=~addr;
            timeout=0;
            while(!top.cart_rom_ready && timeout<2000) begin @(negedge clk);timeout=timeout+1;end
            if(!top.cart_rom_ready) $fatal(1,"FAIL ROM starvation while SRAM active");
            if(top.cart_rd_data!==rom_dword(addr) || top.cart_rd_data_second!==rom_dword(addr+25'd1))
                $fatal(1,"FAIL ROM data after save handoff at %h",addr);
            rom_reads=rom_reads+1;
            @(negedge clk);
        end
    endtask
    reg stress_done=0;
    integer i,rom_index=0;
    reg [7:0] value,ignored;
    initial begin
        repeat(5) @(negedge clk);reset_n=1;
        repeat(4200) @(negedge clk);observe=1;
        fork
            begin
                while(!stress_done) begin
                    // Explicitly straddle 128KiB ROM counter boundaries.
                    case(rom_index%4)
                        0: read_rom(25'h7fff);
                        1: read_rom(25'h8000);
                        2: read_rom(25'h12345);
                        3: read_rom(25'd0);
                    endcase
                    repeat(rom_index%7) @(negedge clk);
                    rom_index=rom_index+1;
                end
            end
            begin
                check_byte(17'h0000,seed_byte(0));
                check_byte(17'h7ff0,seed_byte(16'h7ff0));
                check_byte(17'h7fff,seed_byte(16'h7fff));
                for(i=0;i<4096;i=i+1) begin
                    byte_access(0,i[16:0],8'h00,ignored);
                    check_byte(i[16:0],seed_byte(i));
                end
                if(physical_writes!=0) $fatal(1,"FAIL denied write reached cartridge pins");
                writes_enabled=1;
                // Copy 4KiB through host reads/writes, including 7FF0/7FFF.
                for(i=0;i<4096;i=i+1) begin
                    byte_access(1,i[16:0],0,value);
                    byte_access(0,17'h7000+i[16:0],value,ignored);
                end
                for(i=0;i<4096;i=i+1) check_byte(17'h7000+i[16:0],seed_byte(i));
                check_byte(17'h6fff,seed_byte(16'h6fff));
                writes_enabled=0;
                byte_access(0,17'h7ff0,8'hff,ignored);
                byte_access(0,17'h7fff,8'hff,ignored);
                check_byte(17'h7ff0,seed_byte(16'hff0));
                check_byte(17'h7fff,seed_byte(16'hfff));
                if(physical_writes!=4096 || physical_reads!=host_reads)
                    $fatal(1,"FAIL SRAM duplicate/lost pin transaction reads=%0d/%0d writes=%0d",physical_reads,host_reads,physical_writes);
                stress_done=1;
            end
        join
        if(top.cart_arb.busy || rom_reads<1000) $fatal(1,"FAIL queue did not drain or ROM not exercised");
        $display("PASS SRAM integration: %0d byte reads, %0d copy writes, %0d denied writes, %0d concurrent ROM reads",host_reads,host_writes,denied_writes,rom_reads);
        $finish;
    end
    initial begin #100000000; $fatal(1,"FAIL SRAM integration watchdog");end
endmodule
