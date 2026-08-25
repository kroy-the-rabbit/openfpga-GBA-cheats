// SPDX-License-Identifier: GPL-3.0-or-later
// Testbench for src/fpga/core/cheat_binloader.sv.
//
// Streams a .chtbin file through the loader and prints every 128-bit word that
// reaches gba_cheats, in the order it lands in the table. tools/sim/
// run_binloader.py builds the files and says what should come out.
//
// The words are taken from gba_cheats_model, not from cheat_in directly, so
// the handshake is part of what is being tested: cheat_binloader drives
// cheat_in combinationally from its shift register rather than registering it,
// and the claim that the register is nonetheless stable across the rising edge
// of cheat_on is exactly the sort of claim that should be checked by a model of
// the consumer rather than by reading the code. Run with +gap=0 to check it
// with a byte arriving on every single cycle.
//
//   +f=<path>    the file to send
//   +gap=<n>     clk cycles per byte (default 4, data_loader's floor). 0 holds
//                wr high and sends a byte every cycle, which is four times
//                what data_loader can produce and the tightest the stability
//                window can ever be squeezed.
//
//   iverilog -g2012 -o tb tools/sim/tb_cheat_binloader.sv \
//       tools/sim/gba_cheats_model.sv src/fpga/core/cheat_binloader.sv
//   vvp tb +f=path/to/file.chtbin

`timescale 1ns / 1ps
`default_nettype none

module tb;

  reg        clk = 0;
  reg        reset = 1;
  reg        wr = 0;
  reg  [7:0] data = 8'd0;
  reg        eof = 0;

  wire [127:0] cheat_in;
  wire         cheat_on;
  wire [5:0]   entry_count, group_count, reject_count;
  wire [19:0]  byte_count;
  wire         overrun;

  always #5 clk = ~clk;

  cheat_binloader #(
      .MAX_ENTRIES (32)
  ) dut (
      .clk          (clk),
      .reset        (reset),
      .wr           (wr),
      .data         (data),
      .eof          (eof),
      .cheat_in     (cheat_in),
      .cheat_on     (cheat_on),
      .entry_count  (entry_count),
      .group_count  (group_count),
      .byte_count   (byte_count),
      .reject_count (reject_count),
      .overrun      (overrun)
  );

  wire [31:0] stored, writes;

  gba_cheats_model #(.CHEATCOUNT(32)) cheats (
      .clk      (clk),
      .reset    (1'b0),
      .cheat_on (cheat_on),
      .cheat_in (cheat_in),
      .vsync    (1'b0),
      .stored   (stored),
      .writes   (writes)
  );

  // Print each word as gba_cheats latches it into its table.
  always @(posedge clk)
    if (cheats.cheat_valid)
      $display("WORD %032x", cheats.cheat_in_1);

  integer fd, c, gap;
  reg [31:0] gap_arg;
  reg [8*1024-1:0] fname;

  initial begin
    if (!$value$plusargs("f=%s", fname)) begin
      $display("ERROR: pass +f=<file>");
      $finish;
    end
    gap = 4;
    if ($value$plusargs("gap=%d", gap_arg)) gap = gap_arg;

    fd = $fopen(fname, "rb");
    if (fd == 0) begin
      $display("ERROR: cannot open file");
      $finish;
    end

    repeat (4) @(posedge clk);
    reset <= 1'b0;
    @(posedge clk);

    c = $fgetc(fd);
    while (c != -1) begin
      @(posedge clk);
      data <= c[7:0];
      wr   <= 1'b1;
      // gap 0 leaves wr high and replaces data on the next edge, so the loader
      // sees a byte every cycle with no idle cycle anywhere in the file.
      if (gap != 0) begin
        @(posedge clk);
        wr <= 1'b0;
        repeat (gap - 1) @(posedge clk);
      end
      c = $fgetc(fd);
    end
    @(posedge clk);
    wr <= 1'b0;
    $fclose(fd);

    // The core says when the download is over. Nothing is waiting on it here,
    // since an entry goes out on its sixteenth byte, but a file that ended
    // part way through an entry is only visible at this edge.
    repeat (4) @(posedge clk);
    eof <= 1'b1;
    @(posedge clk);
    eof <= 1'b0;
    repeat (32) @(posedge clk);

    $display("TOTAL bytes=%0d declared=%0d entries=%0d rejected=%0d malformed=%0d stored=%0d",
             byte_count, group_count, entry_count, reject_count, overrun, stored);
    if (stored !== {26'd0, entry_count})
      $display("FAIL: loader counted %0d entries, gba_cheats stored %0d",
               entry_count, stored);
    $finish;
  end

endmodule

`default_nettype wire
