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
// the requested DWORD first and its partner (address ^ 1) second. Hit flags
// are registered from the live read address every clock; the address is held
// from request to ready, which is never fewer than two clocks away, so the
// flags are settled before the data is.
`default_nettype none
module rom_patch #(
    parameter integer SLOTS = 8
) (
    input  wire         clk,

    // the loader's push, as gba_cheats sees it
    input  wire         load_reset,
    input  wire         cheat_on,
    input  wire [127:0] cheat_in,

    // the ROM read stream, DWORD addresses
    input  wire [24:0]  rd_addr,
    input  wire [31:0]  din_first,
    input  wire [31:0]  din_second,
    output wire [31:0]  dout_first,
    output wire [31:0]  dout_second,

    output reg  [3:0]   count        // slots in use
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
        count = 4'd0;
        for (i = 0; i < SLOTS; i = i + 1) begin
            slot_addr[i] = 23'd0; slot_val[i] = 32'd0; slot_be[i] = 4'd0;
        end
    end

    always @(posedge clk) begin
        cheat_on_1 <= cheat_on;
        cheat_in_1 <= cheat_in;
        if (load_reset) begin
            valid <= {SLOTS{1'b0}};
            count <= 4'd0;
        end else if (cheat_on && !cheat_on_1 && entry_rom && entry_plain &&
                     count < SLOTS[3:0]) begin
            slot_addr[count[2:0]] <= entry_addr[24:2];
            slot_val[count[2:0]]  <= cheat_in_1[31:0];
            slot_be[count[2:0]]   <= cheat_in_1[103:100];
            valid[count[2:0]]     <= 1'b1;
            count                 <= count + 4'd1;
        end
    end

    reg [SLOTS-1:0] hit_first, hit_second;
    always @(posedge clk) begin
        for (i = 0; i < SLOTS; i = i + 1) begin
            hit_first[i]  <= valid[i] && rd_addr == {2'b00, slot_addr[i]};
            hit_second[i] <= valid[i] && (rd_addr ^ 25'd1) == {2'b00, slot_addr[i]};
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

    assign dout_first  = apply(din_first,  hit_first);
    assign dout_second = apply(din_second, hit_second);
endmodule

`default_nettype wire
