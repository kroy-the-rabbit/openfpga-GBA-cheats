// SPDX-License-Identifier: GPL-3.0-or-later
// Testbench for src/fpga/core/cheat_loader.sv.
//
// Streams a .cht file through the parser and prints every 128-bit word that
// reaches gba_cheats, in the order it lands in the table. tools/sim/run.py
// compares that against tools/cheats/gbacht.py over the whole libretro GBA
// cheat database.
//
// The words are taken from gba_cheats_model, not from cheat_in directly, so
// the handshake is part of what is being tested: a push that does not hold
// cheat_in stable across the rising edge of cheat_on latches the wrong word
// here, exactly as it would on hardware.
//
//   +f=<path>    the file to send
//   +gap=<n>     clk cycles between bytes (default 4, data_loader's floor)
//
//   iverilog -g2012 -o tb tools/sim/tb_cheat_loader.sv \
//       tools/sim/gba_cheats_model.sv src/fpga/core/cheat_loader.sv
//   vvp tb +f=path/to/file.cht

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

  cheat_loader #(
      .MAX_ENTRIES     (32),
      // Short enough that the testbench does not have to idle for ten
      // milliseconds of simulated time to reach it.
      .IDLE_FLUSH_BITS (8)
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
      @(posedge clk);
      wr   <= 1'b0;
      repeat (gap - 1) @(posedge clk);
      c = $fgetc(fd);
    end
    $fclose(fd);

    // The last cheat in the file has nothing after it to resolve its enable
    // key, so the core says when the download is over.
    repeat (4) @(posedge clk);
    eof <= 1'b1;
    @(posedge clk);
    eof <= 1'b0;
    repeat (200) @(posedge clk);

    $display("TOTAL bytes=%0d cheats=%0d entries=%0d rejected=%0d overrun=%0d stored=%0d",
             byte_count, group_count, entry_count, reject_count, overrun, stored);
    if (overrun) $display("FAIL: push overrun");
    if (stored !== {26'd0, entry_count})
      $display("FAIL: loader counted %0d entries, gba_cheats stored %0d",
               entry_count, stored);
    $finish;
  end

endmodule

`default_nettype wire
