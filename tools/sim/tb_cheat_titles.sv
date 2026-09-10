// SPDX-License-Identifier: GPL-3.0-or-later
// Streams a .cht through cheat_loader into cheat_titles and prints every
// title back out of the RAM: "TITLE <group> <len> <chars as font indices>".
`timescale 1ns/1ps
module tb_cheat_titles;
  reg clk=0; always #5 clk=~clk;
  reg reset=1, wr=0, eof=0; reg [7:0] data=0;
  wire [127:0] cheat_in; wire cheat_on;
  wire [5:0] entry_count, group_count, reject_count; wire [19:0] byte_count; wire overrun;
  wire desc_wr, desc_end; wire [4:0] desc_group, desc_col; wire [5:0] desc_char;
  cheat_loader loader(.clk(clk),.reset(reset),.wr(wr),.data(data),.eof(eof),
    .cheat_in(cheat_in),.cheat_on(cheat_on),.entry_count(entry_count),.group_count(group_count),
    .byte_count(byte_count),.reject_count(reject_count),.overrun(overrun),
    .desc_wr(desc_wr),.desc_group(desc_group),.desc_col(desc_col),.desc_char(desc_char),.desc_end(desc_end));
  reg [4:0] rd_group=0, rd_col=0; wire [5:0] rd_char; wire [4:0] rd_len;
  cheat_titles titles(.wr_clk(clk),.wr_reset(reset),.wr_en(desc_wr),.wr_group(desc_group),.wr_col(desc_col),
    .wr_char(desc_char),.wr_end(desc_end),.rd_clk(clk),.rd_group(rd_group),.rd_col(rd_col),.rd_char(rd_char),.rd_len(rd_len));
  integer fd, c, g, k; reg [1023:0] fname;
  initial begin
    if (!$value$plusargs("f=%s", fname)) begin $display("ERROR: pass +f=<file>"); $finish; end
    fd=$fopen(fname,"rb"); if (fd==0) begin $display("ERROR: cannot open file"); $finish; end
    repeat(4) @(negedge clk); reset=0; repeat(2) @(negedge clk);
    c=$fgetc(fd);
    while (c!=-1) begin
      data=c[7:0]; wr=1; @(negedge clk); wr=0; repeat(3) @(negedge clk);
      c=$fgetc(fd);
    end
    eof=1; @(negedge clk); eof=0; repeat(200) @(negedge clk);
    for (g=0; g<group_count; g=g+1) begin
      rd_group=g; rd_col=0; @(negedge clk); @(negedge clk);
      $write("TITLE %0d %0d", g, rd_len);
      for (k=0; k<rd_len; k=k+1) begin
        rd_col=k; @(negedge clk); @(negedge clk);
        $write(" %0d", rd_char);
      end
      $write("\n");
    end
    $display("GROUPS %0d", group_count);
    $finish;
  end
endmodule
