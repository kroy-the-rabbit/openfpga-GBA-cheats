// SPDX-License-Identifier: GPL-3.0-or-later
// Behavioural stand-in for MiSTer's rtl/gba_cheats.vhd, for Icarus only.
//
// The real module is VHDL, instantiates Altera IP through a SyncFifo and talks
// to the GBA memory mux over a debug bus, none of which will run in a plain
// Verilog simulation. What matters for testing cheat_loader is the contract
// between them, so this reproduces exactly the parts cheat_loader has to get
// right and nothing else:
//
//   * the cheat_on / cheat_in handshake, registered the way gba_cheats does it
//     (cheat_on_1, cheat_in_1, cheat_valid), so a push that does not hold
//     cheat_in stable across the rising edge is caught here rather than on
//     hardware;
//   * the table: CHEATCOUNT slots, all optype F at reset, a new entry landing
//     in the FIRST slot still marked empty;
//   * the apply pass on vsync: walk the table in slot order, stop at the first
//     empty slot, and for each entry read the 32-bit word at bits 91:64,
//     replace the bytes selected by bits 103:100 and write it back;
//   * skip_next: a non-ALWAYS entry writes nothing, compares instead, and on
//     failure suppresses the next slot. This is what makes a conditional code
//     an entry pair, and it is the part most easily got wrong.
//
// The comparisons below are copied from the CHEAT_TEST state of the VHDL, not
// from the names of its constants, because two of those names are inverted.
// See src/fpga/core/cheat_loader.sv.

`default_nettype none

module gba_cheats_model #(
    parameter CHEATCOUNT = 32
) (
    input  wire         clk,
    input  wire         reset,          // gb_on low / cheat_clear

    input  wire         cheat_on,
    input  wire [127:0] cheat_in,

    input  wire         vsync,          // run the apply pass

    // Flat memory, for the testbench to inspect. Word addressed.
    output reg  [31:0]  stored,         // entries currently held
    output reg  [31:0]  writes          // bus writes performed
);

  // ------------------------------------------------- the handshake, exactly --
  reg          cheat_on_1;
  reg [127:0]  cheat_in_1;
  reg          cheat_valid;

  always @(posedge clk) begin
    cheat_on_1  <= cheat_on;
    cheat_in_1  <= cheat_in;
    cheat_valid <= cheat_on & ~cheat_on_1;
  end

  // ------------------------------------------------------------- the table --
  reg [127:0] cheatmem [0:CHEATCOUNT-1];

  // ------------------------------------------------------ the fake GBA bus --
  // Only the regions a cheat may name. Word addressed.
  reg [31:0] ewram [0:65535];   // 0x02000000, 256 KB
  reg [31:0] iwram [0:8191];    // 0x03000000, 32 KB
  reg [31:0] ioreg [0:255];     // 0x04000000, 1 KB

  function automatic [31:0] rd(input [27:0] a);
    begin
      if (a[27:24] == 4'h2)      rd = ewram[a[17:2]];
      else if (a[27:24] == 4'h3) rd = iwram[a[14:2]];
      else if (a[27:24] == 4'h4) rd = ioreg[a[9:2]];
      else                       rd = 32'hDEADBEEF;
    end
  endfunction

  task automatic wrmem(input [27:0] a, input [31:0] d);
    begin
      if (a[27:24] == 4'h2)      ewram[a[17:2]] = d;
      else if (a[27:24] == 4'h3) iwram[a[14:2]] = d;
      else if (a[27:24] == 4'h4) ioreg[a[9:2]] = d;
    end
  endtask

  // Read back for the testbench, one byte at a time.
  function automatic [7:0] peek(input [27:0] a);
    reg [31:0] w;
    begin
      w = rd({a[27:2], 2'b00});
      peek = w[8*a[1:0] +: 8];
    end
  endfunction

  integer i;
  reg [127:0] e;
  reg [31:0]  old;
  reg [31:0]  nw;
  reg         skip_next;
  reg         cond;
  reg         placed;

  initial begin
    for (i = 0; i < 65536; i = i + 1) ewram[i] = 32'd0;
    for (i = 0; i < 8192; i = i + 1)  iwram[i] = 32'd0;
    for (i = 0; i < 256; i = i + 1)   ioreg[i] = 32'd0;
    for (i = 0; i < CHEATCOUNT; i = i + 1) cheatmem[i] = {128{1'b1}};
    stored = 0;
    writes = 0;
  end

  always @(posedge clk) begin
    if (reset) begin
      for (i = 0; i < CHEATCOUNT; i = i + 1) cheatmem[i] = {128{1'b1}};
      stored <= 0;
    end else if (cheat_valid) begin
      // First slot still marked empty takes it. A table already full silently
      // drops the entry, which is what the real module does too.
      placed = 1'b0;
      for (i = 0; i < CHEATCOUNT; i = i + 1)
        if (!placed && cheatmem[i][99:96] == 4'hF) begin
          cheatmem[i] = cheat_in_1;
          placed      = 1'b1;
          stored      = stored + 1;
        end
    end
  end

  // The apply pass. Not cycle accurate: the real one waits for the memory bus
  // to settle and takes several cycles per entry, none of which cheat_loader
  // can observe.
  always @(posedge vsync) begin
    skip_next = 1'b0;
    for (i = 0; i < CHEATCOUNT; i = i + 1) begin
      e = cheatmem[i];
      if (e[99:96] == 4'hF) i = CHEATCOUNT;          // first empty slot ends it
      else if (skip_next) skip_next = 1'b0;
      else begin
        old = rd(e[91:64]);
        if (e[99:96] == 4'h0) begin
          nw = old;
          if (e[100]) nw[7:0]   = e[7:0];
          if (e[101]) nw[15:8]  = e[15:8];
          if (e[102]) nw[23:16] = e[23:16];
          if (e[103]) nw[31:24] = e[31:24];
          wrmem(e[91:64], nw);
          writes = writes + 1;
        end else begin
          if (!e[100]) old[7:0]   = 8'd0;
          if (!e[101]) old[15:8]  = 8'd0;
          if (!e[102]) old[23:16] = 8'd0;
          if (!e[103]) old[31:24] = 8'd0;
          case (e[99:96])
            4'h1: cond = (old != e[31:0]);            // OPTYPE_EQUALS
            4'h2: cond = (old <= e[31:0]);            // OPTYPE_GREATER
            4'h3: cond = (old <  e[31:0]);            // OPTYPE_LESS
            4'h4: cond = (old >= e[31:0]);            // OPTYPE_GREATER_EQ
            4'h5: cond = (old >  e[31:0]);            // OPTYPE_LESS_EQ
            4'h6: cond = (old == e[31:0]);            // OPTYPE_NOT_EQ
            default: cond = 1'b0;
          endcase
          if (cond) skip_next = 1'b1;
        end
      end
    end
  end

endmodule

`default_nettype wire
