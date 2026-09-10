// SPDX-License-Identifier: GPL-3.0-or-later
// Renders one 240x160 frame of the cheat overlay with no titles loaded and
// checks that the header and the "CHEAT nn" placeholders draw, that nothing
// draws outside the used rows, and that nothing is X.
`timescale 1ns/1ps
module tb_cheat_osd_smoke;
    localparam H_ACTIVE=240, H_BLANK=68, V_ACTIVE=160, V_BLANK=68;
    reg clk=0; always #60 clk=~clk;
    reg reset=1, show=1, cart=0;
    reg [31:0] mask=32'h7;   // three cheats on
    reg [5:0] groups=6'd3, codes=6'd5;
    wire [4:0] t_group, t_col, t_len; wire [5:0] t_char;
    wire [5:0] font_ch; wire [2:0] font_row; wire [7:0] font_bits;
    wire active, ink;
    reg de=0, vb=0;
    cheat_titles titles(.wr_clk(clk),.wr_reset(reset),.wr_en(1'b0),.wr_group(5'd0),.wr_col(5'd0),
        .wr_char(6'd0),.wr_end(1'b0),.rd_clk(clk),.rd_group(t_group),.rd_col(t_col),.rd_char(t_char),.rd_len(t_len));
    cheat_font font(.ch(font_ch),.row(font_row),.bits(font_bits));
    cheat_osd dut(.clk(clk),.reset(reset),.show(show),.cart_mode(cart),.de(de),.v_blank(vb),
        .enable_mask(mask),.group_count(groups),.code_count(codes),
        .title_group(t_group),.title_col(t_col),.title_char(t_char),.title_len(t_len),
        .font_ch(font_ch),.font_row(font_row),.font_bits(font_bits),.active(active),.ink(ink));
    integer x, y, frame, ink_hdr=0, ink_rows=0, active_unused=0, xs=0;
    task run_frame;
        begin
            vb=1; de=0; repeat(V_BLANK*(H_ACTIVE+H_BLANK)) @(negedge clk); vb=0;
            for (y=0;y<V_ACTIVE;y=y+1) begin
                for (x=0;x<H_ACTIVE;x=x+1) begin
                    de=1; @(negedge clk);
                    if (frame==1) begin
                        if (active===1'bx || ink===1'bx) xs=xs+1;
                        if (ink && y<16) ink_hdr=ink_hdr+1;
                        if (ink && y>=16 && y<40) ink_rows=ink_rows+1;
                        if (active && y>=40) active_unused=active_unused+1;
                    end
                end
                de=0; repeat(H_BLANK) @(negedge clk);
            end
        end
    endtask
    initial begin
        repeat(4) @(negedge clk); reset=0;
        for (frame=0; frame<2; frame=frame+1) run_frame();
        if (xs!=0) $fatal(1,"FAIL overlay produced X on %0d pixels", xs);
        if (ink_hdr<50) $fatal(1,"FAIL header drew only %0d pixels", ink_hdr);
        if (ink_rows<50) $fatal(1,"FAIL placeholder rows drew only %0d pixels", ink_rows);
        if (active_unused!=0) $fatal(1,"FAIL overlay active on %0d pixels below the list", active_unused);
        $display("PASS cheat overlay smoke: header %0d px, three CHEAT rows %0d px, nothing below row 5", ink_hdr, ink_rows);
        $finish;
    end
endmodule
