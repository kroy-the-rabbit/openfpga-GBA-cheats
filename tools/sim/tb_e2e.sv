// SPDX-License-Identifier: GPL-3.0-or-later
// End to end: APF bridge writes -> data_loader -> the loader -> gba_cheats.
//
// The unit testbenches prove a loader in isolation. This proves the two seams
// around it: the byte stream arriving through data_loader's dual clock FIFO at
// real APF rates, and the entries actually landing in gba_cheats' table and
// poking the right bytes of the right words, conditional pairs included.
//
// Built twice, once per loader. Define BINLOADER for cheat_binloader and a
// packed .chtbin; without it the file is a .cht and cheat_loader parses it.
// The seam is worth testing on both, and more so on the binary one: an entry
// there is sixteen bytes with no framing of its own, so a byte lost in the
// FIFO does not corrupt one entry, it misaligns every entry after it.
//
// The clocks are the real ones: 74.25 MHz on the bridge side, and the 100.66
// MHz clk_sys that gba_top and everything below it run on in this core.
//
//   +f=<path>     the cheat file to send
//   +seed=<path>  memory to preload, lines of "<hex addr> <hex byte>"
//   +e=<path>     expected memory after the apply pass, same line format
//
//   iverilog -g2012 -o tb tools/sim/tb_e2e.sv tools/sim/dcfifo.sv \
//       tools/sim/gba_cheats_model.sv src/fpga/pocket/data_loader.sv \
//       src/fpga/core/cheat_loader.sv

`timescale 1ns/1ps
`default_nettype none

module tb_e2e;

  reg clk_74a = 0;
  reg clk_sys = 0;
  always #6.7340 clk_74a = ~clk_74a;   // 74.25 MHz
  always #4.9672 clk_sys = ~clk_sys;   // 100.66 MHz

  // ------------------------------------------------------------ APF bridge --
  reg        bridge_wr = 0;
  reg [31:0] bridge_addr = 0;
  reg [31:0] bridge_wr_data = 0;

  wire       cheat_wr;
  wire [7:0] cheat_dout;

  data_loader #(
      .ADDRESS_MASK_UPPER_4  (4'h5),
      .ADDRESS_SIZE          (28),
      .OUTPUT_WORD_SIZE      (1),
      .WRITE_MEM_CLOCK_DELAY (4)
  ) dl (
      .clk_74a              (clk_74a),
      .clk_memory           (clk_sys),
      .bridge_wr            (bridge_wr),
      .bridge_endian_little (1'b0),
      .bridge_addr          (bridge_addr),
      .bridge_wr_data       (bridge_wr_data),
      .write_en             (cheat_wr),
      .write_addr           (),
      .write_data           (cheat_dout)
  );

  // -------------------------------------------------------------- the core --
  reg reset = 1;
  reg eof = 0;

  wire [127:0] cheat_in;
  wire         cheat_on;
  wire [5:0]   entry_count, group_count, reject_count;
  wire [19:0]  byte_count;
  wire         overrun;

`ifdef BINLOADER
  cheat_binloader #(
      .MAX_ENTRIES (32)
  ) cl (
`else
  cheat_loader #(
      .MAX_ENTRIES     (32),
      .IDLE_FLUSH_BITS (12)
  ) cl (
`endif
      .clk          (clk_sys),
      .reset        (reset),
      .wr           (cheat_wr),
      .data         (cheat_dout),
      .eof          (eof),
      .cheat_in     (cheat_in),
      .cheat_on     (cheat_on),
      .entry_count  (entry_count),
      .group_count  (group_count),
      .byte_count   (byte_count),
      .reject_count (reject_count),
      .overrun      (overrun)
  );

  reg         vsync = 0;
  wire [31:0] stored, writes;

  gba_cheats_model #(.CHEATCOUNT(32)) cheats (
      .clk      (clk_sys),
      .reset    (1'b0),
      .cheat_on (cheat_on),
      .cheat_in (cheat_in),
      .vsync    (vsync),
      .stored   (stored),
      .writes   (writes)
  );

  // ------------------------------------------------------------- stimulus --
  reg [7:0] fbuf [0:1048575];
  integer   flen, fails = 0;
  reg [8*1024-1:0] fname, sname, ename;
  integer fd, i, n;
  reg [31:0] w;

  // One APF word. APF delivers roughly one every 75 clk_74a cycles; nothing
  // faster than that is a case the hardware can produce.
  task send_word(input [31:0] a, input [31:0] d);
    begin
      @(posedge clk_74a);
      bridge_addr    <= a;
      bridge_wr_data <= d;
      bridge_wr      <= 1'b1;
      @(posedge clk_74a);
      bridge_wr      <= 1'b0;
      repeat (73) @(posedge clk_74a);
    end
  endtask

  task frame;
    begin
      @(posedge clk_sys);
      vsync = 1'b1;
      repeat (4) @(posedge clk_sys);
      vsync = 1'b0;
      repeat (4) @(posedge clk_sys);
    end
  endtask

  integer ea, ev;

  initial begin
    if (!$value$plusargs("f=%s", fname)) begin
      $display("FAIL: no +f=<cht file>");
      $finish;
    end
    fd = $fopen(fname, "rb");
    if (fd == 0) begin
      $display("FAIL: cannot open %0s", fname);
      $finish;
    end
    flen = $fread(fbuf, fd);
    $fclose(fd);

    // Memory the codes will act on, before they act on it. Conditional codes
    // are only worth testing against a value that makes the test go both ways.
    if ($value$plusargs("seed=%s", sname)) begin
      fd = $fopen(sname, "r");
      if (fd == 0) begin
        $display("FAIL: cannot open %0s", sname);
        $finish;
      end
      while ($fscanf(fd, "%h %h\n", ea, ev) == 2)
        cheats.wrmem({ea[27:2], 2'b00},
                     (cheats.rd({ea[27:2], 2'b00})
                      & ~(32'hFF << (8 * ea[1:0])))
                     | ((ev & 32'hFF) << (8 * ea[1:0])));
      $fclose(fd);
    end

    repeat (8) @(posedge clk_sys);
    reset <= 1'b0;
    repeat (4) @(posedge clk_sys);

    // Pad to a whole number of 32-bit words, as APF does.
    for (i = 0; i < flen; i = i + 4) begin
      w = { fbuf[i],
            (i+1 < flen) ? fbuf[i+1] : 8'h00,
            (i+2 < flen) ? fbuf[i+2] : 8'h00,
            (i+3 < flen) ? fbuf[i+3] : 8'h00 };
      send_word(32'h5000_0000 + i, w);
    end

    // The download is over. The core pulses this on the falling edge of the
    // slot 7 write; the ASCII parser needs it to resolve the last cheat's
    // enable key, the binary loader only to notice a file that ended part way
    // through an entry.
    repeat (200) @(posedge clk_sys);
    eof <= 1'b1;
    @(posedge clk_sys);
    eof <= 1'b0;
    repeat (200) @(posedge clk_sys);

    // APF always sends whole 32-bit words, so a file that is not a multiple of
    // four arrives rounded up with zero padding. Both loaders ignore it: the
    // parser as whitespace, the binary one as bytes past the declared count.
    if (byte_count != ((flen + 3) / 4) * 4) begin
      fails = fails + 1;
      $display("FAIL: loader received %0d bytes, expected %0d",
               byte_count, ((flen + 3) / 4) * 4);
    end
    if (overrun) begin
      fails = fails + 1;
      $display("FAIL: push overrun");
    end
    if (stored !== {26'd0, entry_count}) begin
      fails = fails + 1;
      $display("FAIL: loader pushed %0d entries, gba_cheats stored %0d",
               entry_count, stored);
    end

    // Two passes: the poker must be idempotent, not one-shot.
    frame();
    frame();

    $display("RESULT bytes=%0d cheats=%0d entries=%0d rejected=%0d stored=%0d writes=%0d",
             byte_count, group_count, entry_count, reject_count, stored, writes);

    if ($value$plusargs("e=%s", ename)) begin
      fd = $fopen(ename, "r");
      if (fd == 0) begin
        $display("FAIL: cannot open %0s", ename);
        $finish;
      end
      n = 0;
      while ($fscanf(fd, "%h %h\n", ea, ev) == 2) begin
        n = n + 1;
        if (cheats.peek(ea[27:0]) !== ev[7:0]) begin
          fails = fails + 1;
          $display("FAIL: %07x holds %02x, expected %02x",
                   ea, cheats.peek(ea[27:0]), ev);
        end
      end
      $fclose(fd);
      $display("CHECKED %0d bytes of memory", n);
    end

    if (fails == 0) $display("PASS");
    else            $display("FAILURES %0d", fails);
    $finish;
  end

endmodule

`default_nettype wire
