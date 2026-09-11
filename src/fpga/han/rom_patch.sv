// SPDX-License-Identifier: GPL-3.0-or-later
//
// ROM patches on the read side. A cartridge's mask ROM cannot be written and
// the memory bus drops writes to the ROM region, so a code that patches ROM,
// the Action Replay "ROM patch" pair or a CodeBreaker write to 08xxxxxx, has
// nowhere to land. This sits between rom_source_mux and the cache and
// substitutes the patched bytes as the line is fetched, so the CPU sees the
// patched ROM whether it came from the SD card or the slot. A Game Genie.
//
// The table is filled by watching the same push the engine sees: on the
// rising edge of cheat_on, an entry whose address is in 08000000..0DFFFFFF
// and whose optype is a plain write takes the next free slot. The engine gets
// the entry too and its write is acked and dropped by gba_memorymux, which is
// harmless. Conditional codes are not honoured here; a ROM patch is a fixed
// change to the program, not a per-frame poke.
//
// cache.vhd fetches an aligned 8-byte line and rom_source_mux presents it as
// the requested DWORD first and its partner (address ^ 1) second. The
// address is latched on the request, as rom_source_mux latches its word
// order, because the cache is free to move on to its next address before
// the data comes back; the hit flags are registered from that latch.
`default_nettype none
module rom_patch #(
    // A real GBA ROM hack is a run of consecutive halfword writes, not one
    // poke: Zero Mission's two midair-jump cheats are six patches each, and
    // eight slots could not hold both. Thirty-two is the whole cheat table,
    // so the read side can no longer be the thing that runs out first.
    // count is one bit wider than the index, so a full table is
    // distinguishable from an empty one; raising SLOTS again needs both.
    parameter integer SLOTS = 32
) (
    input  wire         clk,

    // the loader's push, as gba_cheats sees it
    input  wire         load_reset,
    input  wire         cheat_on,
    input  wire [127:0] cheat_in,

    // the ROM read stream, DWORD addresses
    input  wire         rd_req,
    input  wire [24:0]  rd_addr,
    input  wire [31:0]  din_first,
    input  wire [31:0]  din_second,
    output wire [31:0]  dout_first,
    output wire [31:0]  dout_second,

    output reg  [5:0]   count,       // slots in use
    output reg          changed      // one clock per table write: invalidate the cache
);
    reg [22:0] slot_addr [0:SLOTS-1];   // ROM DWORD index, 32 MB
    reg [31:0] slot_val  [0:SLOTS-1];
    reg [3:0]  slot_be   [0:SLOTS-1];
    reg [SLOTS-1:0] valid = {SLOTS{1'b0}};

    reg         cheat_on_1 = 1'b0;
    reg [127:0] cheat_in_1 = 128'd0;
    wire [27:0] entry_addr = cheat_in_1[91:64];
    wire        entry_rom  = entry_addr[27:25] == 3'b100 ||   // 08, 09
                             entry_addr[27:25] == 3'b101 ||   // 0A, 0B
                             entry_addr[27:25] == 3'b110;     // 0C, 0D
    wire        entry_plain = cheat_in_1[99:96] == 4'd0;

    integer i;
    initial begin
        count = 6'd0;
        for (i = 0; i < SLOTS; i = i + 1) begin
            slot_addr[i] = 23'd0; slot_val[i] = 32'd0; slot_be[i] = 4'd0;
        end
    end

    initial changed = 1'b0;
    always @(posedge clk) begin
        cheat_on_1 <= cheat_on;
        cheat_in_1 <= cheat_in;
        changed    <= 1'b0;
        if (load_reset) begin
            valid <= {SLOTS{1'b0}};
            count <= 6'd0;
        end else if (cheat_on && !cheat_on_1 && entry_rom && entry_plain &&
                     count < SLOTS[5:0]) begin
            slot_addr[count[4:0]] <= entry_addr[24:2];
            slot_val[count[4:0]]  <= cheat_in_1[31:0];
            slot_be[count[4:0]]   <= cheat_in_1[103:100];
            valid[count[4:0]]     <= 1'b1;
            count                 <= count + 6'd1;
            changed               <= 1'b1;
        end
    end

    reg [24:0] req_addr = 25'd0;
    always @(posedge clk) if (rd_req) req_addr <= rd_addr;

    reg [SLOTS-1:0] hit_first = {SLOTS{1'b0}}, hit_second = {SLOTS{1'b0}};
    always @(posedge clk) begin
        for (i = 0; i < SLOTS; i = i + 1) begin
            hit_first[i]  <= valid[i] && req_addr == {2'b00, slot_addr[i]};
            hit_second[i] <= valid[i] && (req_addr ^ 25'd1) == {2'b00, slot_addr[i]};
        end
    end

    // Lowest slot wins a lane. Two patches on one byte is a file error, not
    // something to arbitrate.
    //
    // Isolate the lowest set bit, then select with a one-hot OR. The obvious
    // form, a walk over the slots with a per-lane `taken` flag, reads better
    // but synthesises as a SLOTS-deep chain of muxes per lane, and this sits
    // on the ROM data return path into the cache. At 8 slots that was free;
    // at 32 it cost 0.36 ns of setup and failed on two seeds. An AND, a
    // two's complement negate and an OR tree do not grow in depth the same
    // way.
    function automatic [31:0] apply(input [31:0] din, input [SLOTS-1:0] hit);
        integer s, k;
        reg [SLOTS-1:0] cand, win;
        reg [7:0] lane;
        begin
            apply = din;
            for (k = 0; k < 4; k = k + 1) begin
                for (s = 0; s < SLOTS; s = s + 1)
                    cand[s] = hit[s] & slot_be[s][k];
                win  = cand & (~cand + {{(SLOTS-1){1'b0}}, 1'b1});
                lane = 8'd0;
                for (s = 0; s < SLOTS; s = s + 1)
                    lane = lane | ({8{win[s]}} & slot_val[s][8*k +: 8]);
                if (|cand) apply[8*k +: 8] = lane;
            end
        end
    endfunction

    assign dout_first  = apply(din_first,  hit_first);
    assign dout_second = apply(din_second, hit_second);
endmodule

`default_nettype wire
