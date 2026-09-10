// SPDX-License-Identifier: GPL-3.0-or-later
// Renders the first title row of the cheat overlay with a known title in the
// title RAM and compares every cell against the font glyph it should hold.
//
// The smoke bench only counts ink, so it cannot see a title drawn one column
// off. This one reads the picture back cell by cell, which is what catches an
// address pipeline that does not match the title RAM's read latency.
`timescale 1ns/1ps
module tb_cheat_osd_titles;
    localparam H_ACTIVE=240, H_BLANK=68, V_ACTIVE=160, V_BLANK=68;
    localparam CELL=6, HDR_ROWS=2, NCHK=8;
    reg clk=0; always #60 clk=~clk;
    reg reset=1, show=1, cart=1, ce=0;
    reg [31:0] mask=32'h1;
    reg [5:0] groups=6'd1, codes=6'd1;
    reg wr_en=0, wr_end=0;
    reg [4:0] wr_col=0; reg [5:0] wr_char=0;
    wire [4:0] t_group, t_col, t_len; wire [5:0] t_char;
    wire [5:0] font_ch; wire [2:0] font_row; wire [7:0] font_bits;
    wire active, ink;
    reg de=0, vb=0;

    // "JUMP IN" as font indices, ASCII - 32.
    reg [5:0] title [0:NCHK-1];
    initial begin
        title[0]="J"-32; title[1]="U"-32; title[2]="M"-32; title[3]="P"-32;
        title[4]=" "-32; title[5]="I"-32; title[6]="N"-32; title[7]=" "-32;
    end

    cheat_titles titles(.wr_clk(clk),.wr_reset(reset),.wr_en(wr_en),.wr_group(5'd0),
        .wr_col(wr_col),.wr_char(wr_char),.wr_end(wr_end),
        .rd_clk(clk),.rd_group(t_group),.rd_col(t_col),.rd_char(t_char),.rd_len(t_len));
    cheat_font font(.ch(font_ch),.row(font_row),.bits(font_bits));
    cheat_osd dut(.clk(clk),.reset(reset),.ce(ce),.show(show),.cart_mode(cart),.de(de),.v_blank(vb),
        .enable_mask(mask),.group_count(groups),.code_count(codes),
        .title_group(t_group),.title_col(t_col),.title_char(t_char),.title_len(t_len),
        .font_ch(font_ch),.font_row(font_row),.font_bits(font_bits),.active(active),.ink(ink));

    // A second font instance, read directly, gives the expected pattern.
    reg [5:0] exp_ch; reg [2:0] exp_row; wire [7:0] exp_bits;
    cheat_font expfont(.ch(exp_ch),.row(exp_row),.bits(exp_bits));

    // seen[cx*8 + glyph_row], rebuilt each frame from the picture. Flat
    // because iverilog will not parse a two dimensional unpacked array here.
    reg [5:0] seen [0:NCHK*8-1];
    integer x, y, frame, i, r, cx, sub, errors;

    task run_frame;
        begin
            vb=1; de=0; ce=0; repeat(2*V_BLANK*(H_ACTIVE+H_BLANK)) @(negedge clk); vb=0;
            for (y=0;y<V_ACTIVE;y=y+1) begin
                for (x=0;x<H_ACTIVE;x=x+1) begin
                    de=1; ce=0; @(negedge clk);
                    if (frame==1 && y>=HDR_ROWS*8 && y<(HDR_ROWS+1)*8 && x<NCHK*CELL) begin
                        cx = x/CELL; sub = x%CELL;
                        if (ink) seen[cx*8+(y%8)] = seen[cx*8+(y%8)] | (6'd1<<(5-sub));
                    end
                    ce=1; @(negedge clk);
                end
                de=0; ce=0; repeat(2*H_BLANK) @(negedge clk);
            end
        end
    endtask

    initial begin
        for (i=0;i<NCHK*8;i=i+1) seen[i]=6'd0;
        errors=0;
        repeat(4) @(negedge clk); reset=0; @(negedge clk);
        // stream the title in exactly as cheat_loader does
        for (i=0;i<NCHK;i=i+1) begin
            wr_en=1; wr_col=i[4:0]; wr_char=title[i]; @(negedge clk);
        end
        wr_en=0; wr_end=1; wr_col=NCHK[4:0]; @(negedge clk); wr_end=0;

        for (frame=0; frame<2; frame=frame+1) run_frame();

        for (i=0;i<NCHK;i=i+1) begin
            for (r=0;r<8;r=r+1) begin
                exp_ch = title[i]; exp_row = r[2:0]; #1;
                if (seen[i*8+r] !== exp_bits[7:2]) begin
                    $display("FAIL cell %0d row %0d: drew %b, expected %b (char %0d)",
                             i, r, seen[i*8+r], exp_bits[7:2], title[i]);
                    errors = errors + 1;
                end
            end
        end
        if (errors != 0) $fatal(1, "FAIL %0d cell rows wrong: the title is drawn at the wrong column", errors);
        $display("PASS cheat overlay titles: %0d cells match the font glyph for their column", NCHK);
        $finish;
    end
endmodule
