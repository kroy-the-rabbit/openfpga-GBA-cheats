// SPDX-License-Identifier: GPL-3.0-or-later
//
// ROM patches on the read side. A cartridge's mask ROM cannot be written and
// the memory bus drops the cheat engine's writes to the ROM region (a CPU
// write reaches a physical cart, for flash carts), so a code that patches ROM,
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
//
// The substituted line is registered, and the read's done is delayed a clock
// to match. The slot walk straight into gba_memorymux's mem_bus_din was the
// core's worst setup path once flash-cart logic joined it, about 10 ns. The
// sources keep their spacing: SDRAM's second DWORD arrives a clock after its
// done, so it is registered a clock after the first. A cache miss costs one
// clock more, against a 480 to 720 ns cartridge line.
`default_nettype none
module rom_patch #(
    // A real GBA ROM hack is a run of consecutive halfword writes, not one
    // poke: Zero Mission's two midair-jump cheats are six patches each, and
    // eight slots could not hold both. Sixteen holds them with four spare.
    //
    // Not more than that. The selection below is a chain whose depth is
    // SLOTS, and every slot is a registered address, value and mask that
    // has to be compared and multiplexed in parallel. Thirty-two was tried
    // three ways (this walk, a one-hot OR, and folding by DWORD at fill
    // time) and all three landed at 96 to 98 % ALMs without closing
    // reliably; docs/BASELINE.md has the numbers. count is one bit wider
    // than the index so a full table is distinguishable from an empty one.
    parameter integer SLOTS = 16
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
    input  wire         rd_ready,     // from the source: din_first valid now
    output reg  [31:0]  dout_first,
    output reg  [31:0]  dout_second,
    output reg          rd_ready_out, // rd_ready a clock later, dout_first valid

    output reg  [4:0]   count,       // slots in use
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
        count = 5'd0;
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
            count <= 5'd0;
        end else if (cheat_on && !cheat_on_1 && entry_rom && entry_plain &&
                     count < SLOTS[4:0]) begin
            slot_addr[count[3:0]] <= entry_addr[24:2];
            slot_val[count[3:0]]  <= cheat_in_1[31:0];
            slot_be[count[3:0]]   <= cheat_in_1[103:100];
            valid[count[3:0]]     <= 1'b1;
            count                 <= count + 5'd1;
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
    function automatic [31:0] apply(input [31:0] din, input [SLOTS-1:0] hit);
        integer s, k;
        reg [3:0] taken;
        begin
            apply = din;
            taken = 4'd0;
            for (s = 0; s < SLOTS; s = s + 1)
                for (k = 0; k < 4; k = k + 1)
                    if (hit[s] && slot_be[s][k] && !taken[k]) begin
                        apply[8*k +: 8] = slot_val[s][8*k +: 8];
                        taken[k] = 1'b1;
                    end
        end
    endfunction

    initial begin
        dout_first = 32'd0; dout_second = 32'd0; rd_ready_out = 1'b0;
    end
    always @(posedge clk) begin
        rd_ready_out <= rd_ready;
        if (rd_ready)     dout_first  <= apply(din_first,  hit_first);
        if (rd_ready_out) dout_second <= apply(din_second, hit_second);
    end
endmodule

`default_nettype wire
