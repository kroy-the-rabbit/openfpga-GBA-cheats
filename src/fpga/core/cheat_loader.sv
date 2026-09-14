// SPDX-License-Identifier: GPL-2.0-or-later
//
// cheat_loader - parse libretro GBA .cht files into gba_cheats entries
//
// NOT SYNTHESISED ANY MORE, AND NOT DEAD CODE. DO NOT DELETE.
//
// The core ships cheat_binloader.sv instead: this module measured 441 ALMs but
// grew the design by 1,285 and cost 0.54 ns of setup at 97 % utilisation, so
// the parse moved to the host as tools/cheats/cht2bin.py. See docs/HANDOFF.md.
//
// It stays in the tree because tools/sim/run.py still compiles it, and that is
// the cross-check which proves tools/cheats/gbacht.py is a faithful model over
// 513 real libretro files. gbacht.py is what cht2bin.py converts with, so
// deleting this module would silently remove the only independent check on the
// thing that now produces every cheat file. The RTL is the reference; the
// Python is the shipping implementation.
//
// Consumes the raw byte stream of a .cht file from data_loader (data slot 7,
// bridge window 0x50000000) and pushes one 128-bit word per cheat entry into
// MiSTer's gba_cheats, on the rising edge of cheat_on. Nothing is decoded
// host-side: the file is plain text sitting next to the ROM.
//
// tools/cheats/gbacht.py is the executable model of this module and carries the
// long-form derivation of the word layout, the optype table and the code
// formats. Keep the two in step; tools/sim cross-checks them over the libretro
// GBA cheat database.
//
// ---------------------------------------------------------------- the word --
//
//   bits  31:0    replacement value, and the operand of a compare entry
//   bits  63:32   not read by gba_cheats
//   bits  91:64   28-bit GBA bus address, word aligned
//   bits  95:92   not read
//   bits  99:96   optype
//   bits 103:100  byte enables for the four bytes of the value
//
// Every access gba_cheats makes is 32-bit. It reads the word at 91:64, replaces
// the bytes selected by the byte-enable nibble and writes it back, so byte and
// halfword codes are encoded by aligning the address down to a word boundary
// and shifting the value into its lane.
//
// A non-ALWAYS entry writes nothing. It reads the word, zeroes the bytes
// outside the mask, compares against bits 31:0, and on failure sets skip_next,
// which suppresses the FOLLOWING entry in the 32-slot table. A conditional code
// is therefore a PAIR of entries and costs two slots.
//
// The optype numbers below are the effective ones, read off the comparisons in
// gba_cheats' CHEAT_TEST state. Two of the constant names there do not describe
// what they do: OPTYPE_LESS (3) skips when memory is less than the operand, so
// the guarded entry runs when memory is greater or equal, and OPTYPE_GREATER_EQ
// (4) is inverted the same way. Emit 3 for "greater or equal", 4 for "less".
//
// ----------------------------------------------------------- what it takes --
//
//   8 digits then 4 digits    CodeBreaker      AAAAAAAA VVVV
//   8 digits then 8 digits    GameShark v1/v2  AAAAAAAA VVVVVVVV
//   12 digits                 CodeBreaker written without a separator
//   16 digits                 GameShark written without a separator
//
// Tokens pair up two at a time; '+', ':' and whitespace all separate them. The
// supported types are the 8/16/32-bit writes and the 16-bit compares. Types
// gba_cheats cannot express - OR, AND, ADD, multi-line fills, ROM patches,
// button tests, pointer chains - are dropped rather than approximated.
//
// GameShark v3, Action Replay v3 and CodeBreaker lines after a type 9
// (CB_ENCRYPT) are encrypted with a per-game seed, and a .cht file gives no
// indication which encoding a code uses: an encrypted pair is eight hex digits
// and eight more, exactly like a raw one. They are rejected on plausibility. A
// raw code's address, masked to 28 bits, lands in EWRAM, IWRAM or IO; an
// encrypted word is uniformly random and almost never does. Operand bits above
// the width a code claims are the second filter, the one mGBA's own detector
// uses. Over the 514-file libretro GBA database this admits 7570 entries and
// not one address outside those three regions.
//
// That filter is the point of the exercise. gamehacking.org's encoder, whose
// output ships as MiSTer-devel/Cheats_MiSTer, does not filter: its GBA files
// carry entries with addresses like 0b070768, encrypted codes run through a raw
// decoder, poking nothing, out of a table with 32 slots in it.
//
// -------------------------------------------------- why a cheat is buffered --
//
// Whether a cheat is on comes from the file, via the cheatN_enable key libretro
// already writes - and writes AFTER the codes it applies to. gba_cheats has no
// per-entry enable and no way to withdraw an entry once pushed, so a cheat's
// entries are collected into a buffer and pushed only once its enable state is
// known: at its enable key, at the start of the next cheat, or at end of file.
// The buffer has two banks so the next cheat can be collected while the
// previous one is still going out.
//
// A cheat is all or nothing. Pushing the part of it that fits would apply half
// a cheat, and could leave a compare entry last in the table where its
// skip_next suppresses an unrelated one. Cheats are taken in file order and a
// later, smaller cheat can still fit after a larger one was skipped.
//

`default_nettype none

module cheat_loader #(
    // Slots in gba_cheats' table (its CHEATCOUNT). The per-cheat buffer is the
    // same depth, so the buffer is never the binding limit.
    parameter MAX_ENTRIES = 32,
    // Bytes must stop arriving for this many clk cycles before end of file is
    // assumed. APF delivers a 32-bit word about every microsecond, roughly a
    // hundred cycles of clk_sys, so 2^20 cannot fire inside a transfer.
    parameter IDLE_FLUSH_BITS = 20
) (
    input  wire         clk,
    input  wire         reset,      // clears the parser and every counter

    input  wire         wr,         // byte strobe from data_loader
    input  wire [7:0]   data,

    // End of file. The last cheat in a file has nothing after it to resolve its
    // enable key, so the core pulses this on the falling edge of the slot 7
    // download. The idle timer is the backstop if that edge never arrives.
    input  wire         eof,

    // To gba_cheats. cheat_in is held stable across the rising edge of cheat_on,
    // which is what its cheat_on_1 / cheat_in_1 pair samples.
    output reg  [127:0] cheat_in,
    output reg          cheat_on,

    // Readout, for the menu. See core_top.sv.
    output reg  [5:0]   entry_count,  // words pushed to gba_cheats
    output reg  [5:0]   group_count,  // cheats pushed
    output reg  [19:0]  byte_count,   // bytes received, parsed or not
    output reg  [5:0]   reject_count, // enabled cheats the table had no room for
    output reg          overrun,      // a push request arrived with one queued

    // The text of `cheatN_desc`, for the on screen list. Streamed a character
    // at a time to cheat_titles as it is parsed, into the slot the next pushed
    // cheat will take; a cheat that is dropped or disabled does not advance
    // the slot, so the next description overwrites it. Same contract as the
    // GB core's loader.
    output reg          desc_wr,
    output reg  [4:0]   desc_group,
    output reg  [4:0]   desc_col,
    output reg  [5:0]   desc_char,    // ASCII - 32, uppercased
    output reg          desc_end      // desc_col is now the length
);

  localparam AW = $clog2(MAX_ENTRIES);      // 5 for 32
  localparam CW = AW + 1;                   // counts, so 0..MAX_ENTRIES fits

  localparam [3:0] OPT_ALWAYS = 4'h0;
  localparam [3:0] OPT_EQ     = 4'h1;
  localparam [3:0] OPT_GT     = 4'h2;
  localparam [3:0] OPT_GE     = 4'h3;   // named OPTYPE_LESS in the VHDL
  localparam [3:0] OPT_LT     = 4'h4;   // named OPTYPE_GREATER_EQ in the VHDL
  localparam [3:0] OPT_LE     = 4'h5;
  localparam [3:0] OPT_NE     = 4'h6;

  // ---------------------------------------------------------------- lexing --
  // Unchanged from the GB core's loader. A keyword only counts as a key once
  // '=' follows it: `_code` is a substring of `notes_codecs`, and a comment
  // reading `# _code means "Facade"` would otherwise emit a patch out of the
  // description after it. Free text is never tokenized.
  localparam [39:0] KEY_CODE   = "_code";
  localparam [39:0] KEY_DESC   = "_desc";
  localparam [55:0] KEY_ENABLE = "_enable";

  reg [55:0] hist;
  reg        pend_code, pend_desc, pend_enable;
  reg        armed_code, armed_desc, armed_enable;
  reg        in_str;        // skipping an uninteresting quoted string
  reg        capturing;     // inside the quoted value of a _desc key
  reg [4:0]  desc_n;        // characters captured so far
  reg        collecting;    // inside the quoted value of a _code key
  localparam TITLE_W = 26;  // cheat_titles is 26 characters wide

  function automatic [5:0] font_index(input [7:0] c);
    reg [7:0] up;
    begin
      up = (c >= "a" && c <= "z") ? (c - 8'd32) : c;
      font_index = (up >= 8'd32 && up <= 8'd95) ? (up - 8'd32) : 6'd0;
    end
  endfunction

  wire [7:0] ch       = data;
  wire       is_quote = (ch == 8'h22);
  wire       is_nl    = (ch == 8'h0A);
  wire       is_space = (ch == " ") || (ch == 8'h09);
  wire       is_dig   = (ch >= "0") && (ch <= "9");
  wire       is_upper = (ch >= "A") && (ch <= "F");
  wire       is_lower = (ch >= "a") && (ch <= "f");
  wire       is_hex   = is_dig | is_upper | is_lower;
  wire       is_alpha = ((ch >= "A") && (ch <= "Z")) || ((ch >= "a") && (ch <= "z"));
  wire       is_alnum = is_alpha | is_dig;
  wire       says_on  = (ch == "t") || (ch == "T") || (ch == "1");
  wire [3:0] nibble   = is_dig   ? (ch - "0")
                      : is_upper ? (ch - "A" + 8'd10)
                                 : (ch - "a" + 8'd10);

  // ---------------------------------------------------------- token buffer --
  // Up to sixteen hex digits, shifted in from the right. A longer run is not a
  // code in any format, so it is dropped whole rather than truncated.
  reg [63:0] tok;
  reg [4:0]  tok_len;
  reg        tok_ovf;

  // Tokens pair up two at a time. op1 holds the first word of a pair.
  reg        have_op1;
  reg [31:0] op1;
  reg        encrypted;     // a CB_ENCRYPT or DEADFACE line was seen

  // ------------------------------------------------------------- pairing --
  wire tok_rdy = (tok_len != 5'd0) && !tok_ovf;
  wire t4  = tok_rdy && (tok_len == 5'd4);
  wire t8  = tok_rdy && (tok_len == 5'd8);
  wire t12 = tok_rdy && (tok_len == 5'd12);
  wire t16 = tok_rdy && (tok_len == 5'd16);

  reg        pair_v;        // a complete (first, second) pair this cycle
  reg        pair_cb;       // it is a CodeBreaker pair
  reg [31:0] pair_a, pair_b;
  reg        keep_op1;      // hold this token as the first word of a pair
  reg [31:0] keep_val;

  always @* begin
    pair_v   = 1'b0;  pair_cb = 1'b0;
    pair_a   = 32'd0; pair_b  = 32'd0;
    keep_op1 = 1'b0;  keep_val = 32'd0;
    if (have_op1 && (t4 || t8)) begin
      pair_v  = 1'b1;
      pair_cb = t4;
      pair_a  = op1;
      pair_b  = t4 ? {16'd0, tok[15:0]} : tok[31:0];
    end else if (t8) begin
      keep_op1 = 1'b1;
      keep_val = tok[31:0];
    end else if (t12) begin
      pair_v = 1'b1; pair_cb = 1'b1;
      pair_a = tok[47:16]; pair_b = {16'd0, tok[15:0]};
    end else if (t16) begin
      pair_v = 1'b1; pair_cb = 1'b0;
      pair_a = tok[63:32]; pair_b = tok[31:0];
    end
    // Anything else drops both this token and any held first word.
  end

  // ------------------------------------------------------------- decoding --
  wire [3:0]  ctype = pair_a[31:28];
  wire [27:0] caddr = pair_a[27:0];

  reg [1:0]  d_width;      // 0 none, 1 byte, 2 halfword, 3 word
  reg [3:0]  d_optype;
  reg [31:0] d_raw;        // value before lane placement
  reg        d_known;      // a type this module understands
  reg        d_cbwrite;
  reg        d_encrypt;    // the rest of the file is encrypted

  always @* begin
    d_width   = 2'd0;
    d_optype  = OPT_ALWAYS;
    d_raw     = 32'd0;
    d_known   = 1'b0;
    d_cbwrite = 1'b0;
    d_encrypt = 1'b0;
    if (pair_cb) begin
      // CodeBreaker, from mGBA's enum GBACodeBreakerType.
      case (ctype)
        4'h0, 4'h1: ;                                   // game id, hook: no effect
        4'h9: d_encrypt = 1'b1;                         // CB_ENCRYPT
        4'h3: if (pair_b[15:8] == 8'd0) begin           // CB_ASSIGN_1
                d_known = 1'b1; d_width = 2'd1; d_raw = {24'd0, pair_b[7:0]};
                d_cbwrite = 1'b1;
              end
        4'h8: begin                                     // CB_ASSIGN_2
                d_known = 1'b1; d_width = 2'd2; d_raw = {16'd0, pair_b[15:0]};
                d_cbwrite = 1'b1;
              end
        4'h7, 4'hA, 4'hB, 4'hC: begin                   // IF_EQ, IF_NE, IF_GT, IF_LT
          d_known  = 1'b1; d_width = 2'd2; d_raw = {16'd0, pair_b[15:0]};
          d_optype = (ctype == 4'h7) ? OPT_EQ
                   : (ctype == 4'hA) ? OPT_NE
                   : (ctype == 4'hB) ? OPT_GT
                                     : OPT_LT;
        end
        default: ;                                      // OR, FILL, AND, ADD, ...
      endcase
    end else begin
      // GameShark v1/v2 raw, from mGBA's enum GBAGameSharkType.
      case (ctype)
        4'h0: if (pair_b[31:8] == 24'd0) begin          // GSA_ASSIGN_1
                d_known = 1'b1; d_width = 2'd1; d_raw = {24'd0, pair_b[7:0]};
              end
        4'h1: if (pair_b[31:16] == 16'd0) begin         // GSA_ASSIGN_2
                d_known = 1'b1; d_width = 2'd2; d_raw = {16'd0, pair_b[15:0]};
              end
        4'h2: begin d_known = 1'b1; d_width = 2'd3; d_raw = pair_b; end
        4'hD: begin                                     // GSA_IF, or a reseed
          if (pair_a == 32'hDEADFACE) d_encrypt = 1'b1;
          else if ((pair_b[31:16] & 16'hFFCF) == 16'd0) begin
            d_known = 1'b1; d_width = 2'd2; d_raw = {16'd0, pair_b[15:0]};
            case (pair_b[21:20])
              2'd0:    d_optype = OPT_EQ;
              2'd1:    d_optype = OPT_NE;
              2'd2:    d_optype = OPT_LE;
              default: d_optype = OPT_GE;
            endcase
          end
        end
        default: ;                                      // list, patch, button, hook
      endcase
    end
  end

  // Align the address down to a word and shift the value into its byte lane.
  wire [27:0] d_addr = {caddr[27:2], 2'b00};
  reg  [3:0]  d_mask;
  reg  [31:0] d_val;
  reg         d_fits;      // this width can be expressed at this alignment

  always @* begin
    d_mask = 4'd0;
    d_val  = 32'd0;
    d_fits = 1'b0;
    case (d_width)
      2'd1: begin
        d_fits = 1'b1;
        d_mask = 4'd1 << caddr[1:0];
        d_val  = {24'd0, d_raw[7:0]} << {caddr[1:0], 3'b000};
      end
      2'd2: begin
        d_fits = ~caddr[0];
        d_mask = caddr[1] ? 4'hC : 4'h3;
        d_val  = caddr[1] ? {d_raw[15:0], 16'd0} : {16'd0, d_raw[15:0]};
      end
      2'd3: begin
        d_fits = (caddr[1:0] == 2'b00);
        d_mask = 4'hF;
        d_val  = d_raw;
      end
      default: ;
    endcase
  end

  // Where a 32-bit debug-bus write is both meaningful and safe. BIOS and ROM
  // are not writable, SRAM at 0x0E000000 is a byte-wide bus that a 32-bit
  // access misreads, and VRAM/OAM/palette are rewritten by the game every frame
  // after the vblank poke lands, so a code there would do nothing anyway.
  wire d_real = (d_addr >= 28'h2000000 && d_addr <= 28'h203FFFF)   // EWRAM
              | (d_addr >= 28'h3000000 && d_addr <= 28'h3007FFF)   // IWRAM
              | (d_addr >= 28'h4000000 && d_addr <= 28'h40003FE);  // IO

  // ROM is patched on the read side (src/fpga/han/rom_patch.sv), but only an
  // explicit CodeBreaker write may land there: the 8+8 forms keep the RAM
  // filter, because a random word hits this 96 MB window too often.
  wire d_rom  = (d_addr >= 28'h8000000 && d_addr <= 28'hDFFFFFF);

  wire d_add = collecting & pair_v & d_known & d_fits
             & (d_real | (d_cbwrite & d_rom))
             & ~encrypted & ~d_encrypt;

  // ------------------------------------------------------------ the buffer --
  // Two banks: the next cheat is collected in one while the previous is still
  // going out of the other. Packed rather than stored as full 128-bit words,
  // because two thirds of the word is zero.
  //   {bytemask[3:0], optype[3:0], address[27:0], value[31:0]}
  localparam EW = 68;
  reg [EW-1:0] gbuf [0:2*MAX_ENTRIES-1];

  // The delimiter stage. A delimiter registers the decoded token here and the
  // collector commits it on the next clock. Decode, collector update and the
  // bank flip in one clock was the design's worst setup path once flash-cart
  // logic joined the fit, -0.512 ns on 2026-09-14: tok_len through pairing,
  // the type decode and the 28-bit range checks into nx_len, cg_len and the
  // bank registers. Bytes arrive at most one in four clocks, so the next
  // byte cannot land before the commit.
  reg          dl_go;        // a decoded token is waiting to be committed
  reg          dl_end;       // its delimiter also ended the value
  reg          dl_add;
  reg [3:0]    dl_optype;
  reg [EW-1:0] dl_entry;

  reg          bank;         // the bank the collector is writing
  reg [CW-1:0] buf_len;
  reg [CW-1:0] cond_at;      // index of a compare entry with nothing after it yet
  reg          has_cond;
  reg          group_done;   // this cheat is closed to further entries
  reg          group_bad;    // more entries than the table could ever hold

  // What the collector's state becomes after this byte's token, before the
  // closing quote is considered. add() from the model, in one expression.
  reg [CW-1:0] nx_len, nx_cond;
  reg          nx_hascond, nx_done, nx_bad, nx_wr;

  always @* begin
    nx_len     = buf_len;
    nx_cond    = cond_at;
    nx_hascond = has_cond;
    nx_done    = group_done;
    nx_bad     = group_bad;
    nx_wr      = 1'b0;
    if (dl_go && dl_add && !group_done) begin
      if (has_cond && (dl_optype != OPT_ALWAYS)) begin
        // Two compares in a row. skip_next suppresses exactly one entry, so a
        // chain cannot be expressed; the alternative is a write that runs when
        // it should not. Drop back to the compare and close the cheat.
        nx_len     = cond_at;
        nx_hascond = 1'b0;
        nx_done    = 1'b1;
      end else if (buf_len == MAX_ENTRIES[CW-1:0]) begin
        nx_bad  = 1'b1;
        nx_done = 1'b1;
      end else begin
        nx_wr      = 1'b1;
        nx_len     = buf_len + 1'b1;
        nx_hascond = (dl_optype != OPT_ALWAYS);
        nx_cond    = buf_len;
      end
    end
  end

  // Closing the cheat: a compare with nothing after it to guard is dropped,
  // along with everything the same cheat put after it.
  wire [CW-1:0] cg_len = nx_hascond ? nx_cond : nx_len;

  // ---------------------------------------------------- cheat waiting on its enable --
  reg          pend_valid;
  reg          pend_bank;
  reg [CW-1:0] pend_len;
  reg          pend_bad;

  // The end-of-file flush, held one cycle. Every other push takes its length
  // from pend_len, a register; this one alone took cg_len, and that dragged
  // the whole token decode (d_optype, nx_len, cg_len) through the adder into
  // entry_count. At 84 % occupancy that was the worst path in the design,
  // -0.138 ns at the 0 C corner on 2026-09-10. The values cannot be read
  // from the collector's registers instead, because a token left half read
  // when the file ends still counts and only the live nx_* say so. So the
  // flush latches them and pushes on the next clock; no more bytes are
  // coming, so the extra cycle costs nothing.
  reg          eof_flush;
  reg          eof_bank;
  reg [CW-1:0] eof_len;
  reg          eof_bad;

  // Room left in gba_cheats' table.
  wire [CW-1:0] room = MAX_ENTRIES[CW-1:0] - entry_count[CW-1:0];

  // ------------------------------------------------------------ the pusher --
  reg [CW-1:0]  fl_idx, fl_len;
  reg           fl_bank;
  reg [1:0]     fl_state;    // 0 idle, 1 read, 2 present the word, 3 raise
  reg [EW-1:0]  fl_q;        // the buffer's registered read port

  // One queued request, so a cheat can be handed over while the previous one is
  // still going out. Two deep is not needed: a cheat is at least a dozen bytes
  // of text and a push is two cycles an entry.
  reg          req_valid, req_bank;
  reg [CW-1:0] req_len;

  // ------------------------------------------------------------ idle timer --
  reg [IDLE_FLUSH_BITS-1:0] idle;
  wire idle_done = (idle == {IDLE_FLUSH_BITS{1'b1}});

  // eof is a single cycle pulse from the core and may land on the same cycle as
  // a byte, which is busy, so it is held until it has been acted on.
  reg  eof_seen;
  wire at_eof = eof_seen | idle_done;

  // A cheat is handed to the pusher from three places, so these name it once:
  // which bank it is in, how many entries, and whether it was already known to
  // be unusable. They are set and read inside the one always block, so they are
  // blocking assignments and nothing continuous may be derived from them.
  reg          push_go, push_bank, push_bad;
  reg [CW-1:0] push_len;

  always @(posedge clk) begin
    if (reset) begin
      hist         <= 56'd0;
      pend_code    <= 1'b0;  pend_desc  <= 1'b0;  pend_enable  <= 1'b0;
      armed_code   <= 1'b0;  armed_desc <= 1'b0;  armed_enable <= 1'b0;
      in_str       <= 1'b0;  collecting <= 1'b0;  capturing    <= 1'b0;
      desc_wr      <= 1'b0;  desc_end   <= 1'b0;  desc_group   <= 5'd0;
      desc_col     <= 5'd0;  desc_char  <= 6'd0;  desc_n       <= 5'd0;
      tok          <= 64'd0; tok_len    <= 5'd0;  tok_ovf      <= 1'b0;
      have_op1     <= 1'b0;  op1        <= 32'd0; encrypted    <= 1'b0;
      bank         <= 1'b0;  buf_len    <= 0;     cond_at      <= 0;
      has_cond     <= 1'b0;  group_done <= 1'b0;  group_bad    <= 1'b0;
      pend_valid   <= 1'b0;  pend_bank  <= 1'b0;  pend_len     <= 0;
      pend_bad     <= 1'b0;
      eof_flush    <= 1'b0;  eof_bank   <= 1'b0;  eof_len      <= 0;
      eof_bad      <= 1'b0;
      dl_go        <= 1'b0;  dl_end     <= 1'b0;  dl_add       <= 1'b0;
      dl_optype    <= 4'd0;  dl_entry   <= 0;
      req_valid    <= 1'b0;  req_bank   <= 1'b0;  req_len      <= 0;
      fl_idx       <= 0;     fl_len     <= 0;     fl_bank      <= 1'b0;
      fl_state     <= 2'd0;  fl_q       <= 0;     eof_seen     <= 1'b0;
      cheat_in     <= 128'd0;
      cheat_on     <= 1'b0;
      entry_count  <= 6'd0;  group_count <= 6'd0; byte_count   <= 20'd0;
      reject_count <= 6'd0;  overrun     <= 1'b0;
      idle         <= 0;
    end else begin
      push_go   = 1'b0;
      push_bank = 1'b0;
      push_len  = 0;
      push_bad  = 1'b0;
      // one cycle strobes into cheat_titles
      desc_wr   <= 1'b0;
      desc_end  <= 1'b0;

      // ----------------------------------------------------- push sequencer --
      // gba_cheats registers cheat_on and cheat_in and writes cheat_in_1 into
      // its FIFO on the cycle after it sees cheat_on rise, so cheat_in must be
      // stable through the cycle in which cheat_on is first high. State 3 is
      // that cycle. State 1 exists so the buffer is read synchronously, which
      // is what lets it infer as a block RAM instead of a wall of LUT RAM.
      case (fl_state)
        2'd1: begin
          fl_q     <= gbuf[{fl_bank, fl_idx[AW-1:0]}];
          cheat_on <= 1'b0;
          fl_state <= 2'd2;
        end
        2'd2: begin
          cheat_in <= {24'd0, fl_q[67:64], fl_q[63:60], 4'd0,
                       fl_q[59:32], 32'd0, fl_q[31:0]};
          cheat_on <= 1'b0;
          fl_state <= 2'd3;
        end
        2'd3: begin
          cheat_on <= 1'b1;
          if (fl_idx + 1'b1 == fl_len) fl_state <= 2'd0;
          else begin
            fl_idx   <= fl_idx + 1'b1;
            fl_state <= 2'd1;
          end
        end
        default: begin
          cheat_on <= 1'b0;
          if (req_valid) begin
            req_valid <= 1'b0;
            fl_bank   <= req_bank;
            fl_len    <= req_len;
            fl_idx    <= 0;
            fl_state  <= 2'd1;
          end
        end
      endcase

      // -------------------------------------------------------- idle timer --
      // Only runs while there is something an end of file would resolve.
      if (eof) eof_seen <= 1'b1;
      if (wr) idle <= 0;
      else if (!idle_done && (pend_valid || collecting)) idle <= idle + 1'b1;

      // ------------------------------------------------- delimiter commit --
      // Before byte arrival, so a delimiter landing here re-arms dl_go.
      if (dl_go) begin
        dl_go      <= 1'b0;
        buf_len    <= nx_len;
        cond_at    <= nx_cond;
        has_cond   <= nx_hascond;
        group_done <= nx_done;
        group_bad  <= nx_bad;
        if (nx_wr) gbuf[{bank, buf_len[AW-1:0]}] <= dl_entry;

        if (dl_end) begin
          // End of the value: park this cheat until its enable is known.
          collecting <= 1'b0;
          have_op1   <= 1'b0;
          buf_len    <= 0;
          cond_at    <= 0;
          has_cond   <= 1'b0;
          group_done <= 1'b0;
          group_bad  <= 1'b0;
          if (cg_len != 0) begin
            // Structurally there can be nothing parked here: the opening
            // quote of this cheat handed the previous one over. Raised
            // rather than silently overwritten, so the invariant is
            // checkable in simulation instead of assumed.
            if (pend_valid) overrun <= 1'b1;
            pend_valid <= 1'b1;
            pend_bank  <= bank;
            pend_len   <= cg_len;
            pend_bad   <= nx_bad;
            bank       <= ~bank;
          end
        end
      end

      // ------------------------------------------------------ byte arrival --
      if (wr) begin
        // Counts every byte handed over, parsed or not. Distinguishes "the file
        // never arrived" from "it arrived and produced nothing", which is
        // otherwise guesswork on a handheld.
        if (byte_count != {20{1'b1}}) byte_count <= byte_count + 20'd1;

        if (collecting) begin
          if (is_hex) begin
            if (tok_len == 5'd16) tok_ovf <= 1'b1;
            else begin
              tok     <= {tok[59:0], nibble};
              tok_len <= tok_len + 5'd1;
            end
          end else begin
            // A delimiter. Flush the token, which may complete a pair and add
            // an entry, then see whether the value itself has ended.
            tok_len  <= 5'd0;
            tok_ovf  <= 1'b0;
            // Only an actual token decides the pairing. Two delimiters in a
            // row (`AAAAAAAA + VVVV`) must not throw away the held first word.
            if (tok_len != 5'd0) begin
              have_op1 <= keep_op1;
              op1      <= keep_val;
            end
            if (d_encrypt && pair_v) encrypted <= 1'b1;

            // The collector takes it on the next clock.
            dl_go     <= 1'b1;
            dl_end    <= is_quote || is_nl;
            dl_add    <= d_add;
            dl_optype <= d_optype;
            dl_entry  <= {d_mask, d_optype, d_addr, d_val};
          end
        end else if (in_str) begin
          if (is_quote) begin
            in_str    <= 1'b0;
            capturing <= 1'b0;
            if (capturing) begin
              desc_end <= 1'b1;
              desc_col <= desc_n;               // the length
            end
          end else if (capturing && desc_n < TITLE_W[4:0]) begin
            // desc_col names the column of this character, on the same clock
            // as the strobe; the running count is kept apart from it.
            desc_wr   <= 1'b1;
            desc_char <= font_index(ch);
            desc_col  <= desc_n;
            desc_n    <= desc_n + 5'd1;
          end
        end else if (armed_enable && is_alnum) begin
          // The value of a cheatN_enable key: the first word after it. "true"
          // and "1" mean on; anything else means off and the cheat is dropped.
          if (pend_valid) begin
            pend_valid <= 1'b0;
            if (says_on) begin
              push_go   = 1'b1;
              push_bank = pend_bank;
              push_len  = pend_len;
              push_bad  = pend_bad;
            end
          end
          armed_enable <= 1'b0;
          pend_code    <= 1'b0; pend_desc <= 1'b0; pend_enable <= 1'b0;
          hist         <= 56'd0;
        end else if (is_quote) begin
          armed_code   <= 1'b0; armed_desc <= 1'b0; armed_enable <= 1'b0;
          pend_code    <= 1'b0; pend_desc  <= 1'b0; pend_enable  <= 1'b0;
          hist         <= 56'd0;
          if (armed_code) begin
            // A new cheat starts. Whatever is parked had no enable key at all,
            // which means on, so a hand-written file of nothing but codes works.
            if (pend_valid) begin
              pend_valid <= 1'b0;
              push_go    = 1'b1;
              push_bank  = pend_bank;
              push_len   = pend_len;
              push_bad   = pend_bad;
            end
            collecting <= 1'b1;
            tok_len    <= 5'd0;
            tok_ovf    <= 1'b0;
            have_op1   <= 1'b0;
            buf_len    <= 0;
            cond_at    <= 0;
            has_cond   <= 1'b0;
            group_done <= 1'b0;
            group_bad  <= 1'b0;
          end else begin
            in_str <= 1'b1;
            if (armed_desc) begin
              capturing  <= 1'b1;
              desc_group <= group_count[4:0];
              desc_n     <= 5'd0;
            end
          end
        end else begin
          hist <= {hist[47:0], ch};
          if ({hist[47:0], ch} == KEY_ENABLE) begin
            pend_enable <= 1'b1;  pend_code  <= 1'b0;  pend_desc    <= 1'b0;
            armed_code  <= 1'b0;  armed_desc <= 1'b0;  armed_enable <= 1'b0;
          end else if ({hist[31:0], ch} == KEY_CODE) begin
            pend_code   <= 1'b1;  pend_desc  <= 1'b0;  pend_enable  <= 1'b0;
            armed_code  <= 1'b0;  armed_desc <= 1'b0;  armed_enable <= 1'b0;
          end else if ({hist[31:0], ch} == KEY_DESC) begin
            pend_desc   <= 1'b1;  pend_code  <= 1'b0;  pend_enable  <= 1'b0;
            armed_code  <= 1'b0;  armed_desc <= 1'b0;  armed_enable <= 1'b0;
          end else if (ch == "=") begin
            // Only now is it a key. Whatever was pending becomes armed.
            armed_code   <= pend_code;
            armed_desc   <= pend_desc;
            armed_enable <= pend_enable;
            pend_code    <= 1'b0;  pend_desc <= 1'b0;  pend_enable <= 1'b0;
          end else if (!is_space) begin
            // Anything else between the keyword and '=' means it was not a key,
            // just those characters inside a longer word or a comment.
            pend_code    <= 1'b0;  pend_desc <= 1'b0;  pend_enable <= 1'b0;
          end
        end
      end else if (at_eof && !dl_go && collecting && tok_len != 5'd0) begin
        // A token left half read when the file ended still counts, exactly as
        // a delimiter would have flushed it: through the delimiter stage, then
        // the end of file is taken with nothing left in the token.
        tok_len   <= 5'd0;
        tok_ovf   <= 1'b0;
        dl_go     <= 1'b1;
        dl_end    <= 1'b0;
        dl_add    <= d_add;
        dl_optype <= d_optype;
        dl_entry  <= {d_mask, d_optype, d_addr, d_val};
      end else if (at_eof && !dl_go && (pend_valid || collecting)) begin
        // Nothing more is coming. An unterminated value ends here, and whatever
        // is parked goes out with no enable key, which means on.
        idle       <= 0;
        eof_seen   <= 1'b0;
        collecting <= 1'b0;
        have_op1   <= 1'b0;
        tok_len    <= 5'd0;
        tok_ovf    <= 1'b0;
        buf_len    <= 0;
        cond_at    <= 0;
        has_cond   <= 1'b0;
        group_done <= 1'b0;
        group_bad  <= 1'b0;
        if (pend_valid) begin
          pend_valid <= 1'b0;
          eof_flush  <= 1'b1;
          eof_bank   <= pend_bank;
          eof_len    <= pend_len;
          eof_bad    <= pend_bad;
        end else if (cg_len != 0) begin
          // collecting, with a cheat in the buffer and no closing quote
          bank      <= ~bank;
          eof_flush <= 1'b1;
          eof_bank  <= bank;
          eof_len   <= cg_len;
          eof_bad   <= nx_bad;
        end
      end else if (eof_flush) begin
        // The cycle after: everything the push needs is now a register.
        eof_flush <= 1'b0;
        push_go   = 1'b1;
        push_bank = eof_bank;
        push_len  = eof_len;
        push_bad  = eof_bad;
      end

      // ------------------------------------------------- hand over a cheat --
      if (push_go) begin
        if (push_bad || push_len == 0 || push_len > room) begin
          if (push_len != 0 && reject_count != 6'h3F)
            reject_count <= reject_count + 6'd1;
        end else if (req_valid) begin
          // Unreachable with a real file: a cheat is at least a dozen bytes of
          // text apart from the next and a push is two cycles an entry. Raised
          // rather than silently dropped, so it is visible in the readout.
          overrun <= 1'b1;
        end else begin
          req_valid   <= 1'b1;
          req_bank    <= push_bank;
          req_len     <= push_len;
          entry_count <= entry_count + push_len;
          group_count <= group_count + 6'd1;
        end
      end
    end
  end

endmodule

`default_nettype wire
