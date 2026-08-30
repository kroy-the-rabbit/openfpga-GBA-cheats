// SPDX-License-Identifier: GPL-2.0-or-later
//
// cheat_binloader - load a packed .chtbin file into gba_cheats
//
// This replaces cheat_loader, which parsed libretro .cht ASCII on the FPGA.
// That module fitted, at 441 ALMs, but it grew the whole design by 1,285 and
// cost 0.54 ns of setup. docs/HANDOFF.md run M shows why: its cost is
// combinational, a 64-bit token shift register feeding hex conversion, key
// matching, a CodeBreaker pair collector and a wide decoder, and the fitter
// retimed a file parser as though it were on the critical path. No constraint
// reached that, because there was nothing wrong with the constraint.
//
// So the parse moved to the host. tools/cheats/cht2bin.py now produces a file
// that already holds the words gba_cheats consumes, and docs/CHEATBIN.md is
// the contract between the two. What is left here is a byte counter, a shift
// register and a two-state sequencer. It performs no transformation on the
// data at all: no hex, no arithmetic on a cheat, no decisions about what a
// code means. Everything that used to be a decision is now a byte in a file.
//
// ------------------------------------------------------------- the format --
//
// Little-endian throughout. A 16-byte header, then entry_count 16-byte
// entries, and nothing else.
//
//   header  0..3   magic "GBAC", bytes 47 42 41 43
//           4      version, 1
//           5      reserved
//           6..7   entry_count, uint16
//           8..15  reserved
//
//   entry   0..3   value, the operand of a write or of a compare
//           4..7   reserved, gba_cheats does not read bits 63:32
//           8..11  address, 28 bits, so byte 11's high nibble is reserved
//           12     low nibble optype, high nibble byte enables
//           13..15 reserved
//
// The magic is a safety interlock rather than decoration. The format this
// replaces was a plain .cht sitting next to the ROM, so somebody dropping the
// old file in is not a hypothetical, and shifting ASCII into the cheat table
// would poke arbitrary addresses in a running game. A header that does not
// match loads zero entries and the module then stays quiet for the whole file:
// a wrong file behaves as no cheats, never as garbage cheats.
//
// Entry order is significant and is preserved exactly. gba_cheats expresses a
// condition as a compare entry immediately followed by the entry it guards, so
// reordering or dropping one entry of a pair silently changes what the other
// one does. Nothing here sorts, dedupes or filters.
//
// ----------------------------------------------------- 72 bits, not 128 --
//
// The file entry is 16 bytes but only 68 bits of it reach gba_cheats: bits
// 63:32, 95:92 and 127:104 of the word are not read by it at all, and the
// format defines them as zero. Storing them would be 56 flops that no consumer
// ever looks at, which on a design that is 97 % full is the wrong trade, so
// the shift register keeps only the nine bytes that carry meaning and the
// output drives the rest as constants. A file with junk in a reserved byte
// therefore loads as though that byte were zero, which is what the format says
// it must be. The one visible consequence is that this loader cannot be used
// to smuggle data through those bits later; if that is ever wanted, widen the
// register and the byte mask below together.
//
// ---------------------------------------------------------- the handshake --
//
// gba_cheats registers cheat_on and cheat_in, and writes cheat_in_1 into its
// FIFO on the cycle AFTER it sees cheat_on rise, so cheat_in has to be stable
// through the cycle in which cheat_on is first high. Here cheat_in is the
// shift register itself, and the last byte that changes it is byte 12 of the
// entry: bytes 13, 14 and 15 are reserved and are not shifted in. So by the
// time the entry completes, the word has already been stable for three byte
// times, and it stays stable until byte 0 of the next entry. cheat_on is
// raised on the cycle after the sixteenth byte and held for exactly one cycle,
// which lands inside that window even if bytes were to arrive back to back,
// which is four times faster than data_loader can deliver them.
//
// -------------------------------------------------------------- the readout --
//
// The five diagnostic outputs are the ones core_top's CL:/CD: bridge readout
// already reads, kept so that readout keeps working. Two of them no longer
// mean what their names say, because there is no longer any such thing as a
// cheat here, only entries:
//
//   entry_count   entries pushed to gba_cheats. Unchanged.
//   group_count   entries the header DECLARED, not cheats. Reading it against
//                 entry_count is how a truncated or over-long file shows up:
//                 the file said eight, we pushed seven.
//   byte_count    bytes received, used or not. Unchanged, and still the thing
//                 that separates "the file never arrived" from "it arrived and
//                 produced nothing", which is otherwise guesswork on a
//                 handheld with no console.
//   reject_count  declared entries past MAX_ENTRIES, so the table had no room.
//                 The declared count saturates at 63 (see todo below), so this
//                 stops climbing at 31; it is a "there were more" indicator,
//                 not an exact tally, and the file should not contain more in
//                 the first place.
//   overrun       the file was malformed: wrong magic, wrong version, or it
//                 ended in the middle of an entry. The old meaning, a push
//                 arriving with one already queued, cannot happen now that a
//                 push is one cycle with no queue behind it, and this is the
//                 one condition that otherwise looks identical to a valid file
//                 with no cheats in it.
//

`default_nettype none

module cheat_binloader #(
    // Slots in gba_cheats' table (its CHEATCOUNT). Entries past this are
    // counted and dropped rather than wrapped over the ones already loaded.
    // The readout ports are six bits, so this must stay under 64.
    parameter MAX_ENTRIES = 32
) (
    input  wire         clk,
    input  wire         reset,      // clears the loader and every counter

    input  wire         wr,         // byte strobe from data_loader
    input  wire [7:0]   data,

    // End of file, the falling edge of the slot 7 download. Unlike the ASCII
    // parser, this loader needs no flush: an entry completes on its sixteenth
    // byte and goes out there, and a partial entry is simply never completed.
    // eof is kept because it is the only way to notice that the file ended
    // mid-entry, which is a diagnostic worth having and costs one comparison.
    input  wire         eof,

    // To gba_cheats. See the handshake note above.
    output wire [127:0] cheat_in,
    output reg          cheat_on,

    // Readout, for the menu. See core_top.sv and the note above: group_count
    // and overrun do not mean what they meant in cheat_loader.
    output reg  [5:0]   entry_count,
    output reg  [5:0]   group_count,
    output reg  [19:0]  byte_count,
    output reg  [5:0]   reject_count,
    output reg          overrun
);

  localparam [31:0] MAGIC   = 32'h43414247;   // "GBAC" with byte 0 in the LSB
  localparam [7:0]  VERSION = 8'd1;

  // Nine bytes of every sixteen carry meaning. Held little-endian, byte 0 in
  // the LSB, so the register is filled by shifting DOWN and the first byte
  // received ends up at the bottom.
  reg [71:0] sr;

  // Offset inside the current sixteen bytes, and whether those sixteen are the
  // header. Between them these are the whole state machine.
  reg [3:0]  pos;
  reg        hdr;

  // Entries still expected from the file. Loaded from the header and counted
  // down, so trailing bytes past the declared count are ignored rather than
  // loaded as cheats: a byte of garbage on the end of the file is otherwise
  // indistinguishable from a real entry, since entries have no framing of
  // their own. Saturated at 63 because nothing above MAX_ENTRIES can be
  // loaded anyway and a full 16-bit down counter would cost more than the
  // distinction is worth.
  reg [5:0]  todo;

  // Which bytes of the current sixteen are worth keeping. In the header that
  // is 0..7, which covers magic, version and the count; in an entry it is
  // 0..3 (the value), 8..11 (the address) and 12 (optype and byte enables).
  // Both fall out as one small function of pos, because the fields gba_cheats
  // does not read happen to sit at the top of each group of the word. That is
  // luck rather than design, but it is what makes the skipping free.
  wire keep = hdr ? (pos < 4'd8)
                  : (pos < 4'd4) || ((pos >= 4'd8) && (pos <= 4'd12));

  wire done = (pos == 4'd15);            // the sixteenth byte of the block
  // entry_count is six bits and MAX_ENTRIES is an integer, so this compares
  // unsigned-extended and is exact for any MAX_ENTRIES the ports can express.
  wire full = (entry_count == MAX_ENTRIES);
  wire pend = (todo != 6'd0);

  // Header fields, read out of sr on the sixteenth byte. Bytes 8..15 of the
  // header are reserved and not kept, so sr has not moved since byte 7 and
  // still holds byte 0 at [15:8] through byte 7 at [71:64].
  wire        hdr_ok  = (sr[39:8] == MAGIC) && (sr[47:40] == VERSION);
  wire        declmax = |sr[71:62];      // declared count above 63
  wire [5:0]  decl    = declmax ? 6'h3F : sr[61:56];

  // The entry, once nine bytes have been shifted in: byte 0 at [7:0] through
  // byte 12 at [71:64]. The zeroes are the fields gba_cheats does not read.
  assign cheat_in = {24'd0,        // 127:104 unread
                     sr[71:64],    // 103:96  byte enables and optype
                     4'd0,         // 95:92   unread
                     sr[59:32],    // 91:64   address, 28 bits
                     32'd0,        // 63:32   unread
                     sr[31:0]};    // 31:0    value

  always @(posedge clk) begin
    if (reset) begin
      sr           <= 72'd0;
      pos          <= 4'd0;
      hdr          <= 1'b1;
      todo         <= 6'd0;
      cheat_on     <= 1'b0;
      entry_count  <= 6'd0;  group_count <= 6'd0;  byte_count <= 20'd0;
      reject_count <= 6'd0;  overrun     <= 1'b0;
    end else begin
      // One cycle wide unless the block below raises it again.
      cheat_on <= 1'b0;

      if (wr) begin
        // Counts every byte handed over, kept or not, header included.
        if (byte_count != {20{1'b1}}) byte_count <= byte_count + 20'd1;

        if (keep) sr <= {data, sr[71:8]};
        pos <= pos + 4'd1;

        if (done) begin
          if (hdr) begin
            // Whatever the verdict, the header is over. A bad one leaves todo
            // at zero, which is what makes the rest of the file inert: there
            // is no separate "rejected" state to get out of sync.
            hdr <= 1'b0;
            if (hdr_ok) begin
              todo        <= decl;
              group_count <= decl;
            end else begin
              overrun <= 1'b1;
            end
          end else if (pend) begin
            todo <= todo - 6'd1;
            if (full) begin
              // The converter is supposed to enforce the ceiling, so this is a
              // malformed-file path, not a normal one. Dropping the excess is
              // the only safe answer: wrapping would overwrite entries already
              // loaded and could separate a compare from the entry it guards.
              if (reject_count != 6'h3F) reject_count <= reject_count + 6'd1;
            end else begin
              entry_count <= entry_count + 6'd1;
              cheat_on    <= 1'b1;
            end
          end
        end
      end else if (eof && (pos != 4'd0)) begin
        // The file ended part way through a block, so its length was not a
        // multiple of sixteen. The partial entry is discarded by never being
        // completed; this only records that it happened.
        //
        // Guarded by the else because eof and wr racing over pos would flag a
        // good file. They cannot in practice: the core raises eof on the
        // falling edge of the download, long after data_loader's FIFO has
        // drained, and the last byte of a whole file leaves pos at zero.
        overrun <= 1'b1;
      end
    end
  end

endmodule

`default_nettype wire
