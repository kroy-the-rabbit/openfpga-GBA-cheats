// SPDX-License-Identifier: GPL-3.0-or-later
`default_nettype none
// Passive BMXE header check at the ROM mux output, before cache.vhd.
// Sample the first DWORD on ready and the second on the FOLLOWING clock,
// exactly as the cache does. Never drives or stalls the functional ROM bus.
// Reference: first 192 bytes of the verified 8 MiB BMXE cartridge dump,
// SHA256 fc94f65380b65b870a30b9b04b39cca1dc63d6e46a4a373d3904adc0912ebc37.
// Only enable for BMXE. Resetting the GBA CPU alone preserves evidence;
// dropping enable (cartridge mode/identity lost) starts a new observation.
module cart_header_check (
    input wire clk, enable,
    input wire rd_req,
    input wire [24:0] rd_addr, // DWORD address, same as rom_source_mux
    input wire rd_ready,
    input wire [31:0] rd_data, rd_data_second,
    output wire [31:0] diagnostic
);
    // A synchronous ROM can live in one M10K rather than ALMs. It has no
    // reset on its read port; validity comes from the request/response FSM.
    (* romstyle = "M10K" *) reg [31:0] header_rom [0:63];
    integer i;
    initial begin
        for (i = 0; i < 64; i = i + 1) header_rom[i] = 32'd0;
        header_rom[0] = 32'hea00002e;
        header_rom[1] = 32'h51aeff24;
        header_rom[2] = 32'h21a29a69;
        header_rom[3] = 32'h0a82843d;
        header_rom[4] = 32'had09e484;
        header_rom[5] = 32'h988b2411;
        header_rom[6] = 32'h217f81c0;
        header_rom[7] = 32'h19be52a3;
        header_rom[8] = 32'h20ce0993;
        header_rom[9] = 32'h4a4a4610;
        header_rom[10] = 32'hec3127f8;
        header_rom[11] = 32'h33e8c758;
        header_rom[12] = 32'hbfcee382;
        header_rom[13] = 32'h94dff485;
        header_rom[14] = 32'hc1094bce;
        header_rom[15] = 32'hc08a5694;
        header_rom[16] = 32'hfca77213;
        header_rom[17] = 32'h734d849f;
        header_rom[18] = 32'h619acaa3;
        header_rom[19] = 32'h27a39758;
        header_rom[20] = 32'h769803fc;
        header_rom[21] = 32'h61c71d23;
        header_rom[22] = 32'h56ae0403;
        header_rom[23] = 32'h008438bf;
        header_rom[24] = 32'hfd0ea740;
        header_rom[25] = 32'h03fe52ff;
        header_rom[26] = 32'hf130956f;
        header_rom[27] = 32'h85c0fb97;
        header_rom[28] = 32'h2580d660;
        header_rom[29] = 32'h03be63a9;
        header_rom[30] = 32'he2384e01;
        header_rom[31] = 32'hff34a2f9;
        header_rom[32] = 32'h44033ebb;
        header_rom[33] = 32'hcb900078;
        header_rom[34] = 32'h943a1188;
        header_rom[35] = 32'h637cc065;
        header_rom[36] = 32'haf3cf087;
        header_rom[37] = 32'h8be425d6;
        header_rom[38] = 32'h72ac0a38;
        header_rom[39] = 32'h07f8d421;
        header_rom[40] = 32'h4f52455a;
        header_rom[41] = 32'h5353494d;
        header_rom[42] = 32'h454e4f49;
        header_rom[43] = 32'h45584d42;
        header_rom[44] = 32'h00963130;
        header_rom[45] = 32'h00000000;
        header_rom[46] = 32'h00000000;
        header_rom[47] = 32'h00001d00;
    end

    reg pending = 0, in_header = 0, second_due = 0;
    reg [5:0] request_word = 0;
    reg [31:0] expected_word;
    // Request edge fetches word one. Ready edge compares that registered
    // value while fetching its companion, used by the next clock's compare.
    wire [5:0] reference_addr = rd_req ? rd_addr[5:0] :
                                (rd_ready ? request_word ^ 6'd1 : request_word);
    always @(posedge clk) expected_word <= header_rom[reference_addr];
    reg [23:0] seen_lines = 0;
    reg [7:0] checked_pairs = 0;
    reg mismatch = 0, protocol_error = 0;
    reg [5:0] bad_offset = 0; // DWORD offset, exported as byte offset
    reg [3:0] bad_lanes = 0;  // byte lanes of the first bad DWORD that differed
    reg bad_second = 0;       // the first bad DWORD was the companion beat
    wire compare_valid = second_due || (rd_ready && pending && in_header);
    wire [31:0] compare_word = second_due ? rd_data_second : rd_data;
    wire [31:0] compare_diff = compare_word ^ expected_word;
    wire [3:0] compare_lanes = {|compare_diff[31:24], |compare_diff[23:16],
                                |compare_diff[15:8], |compare_diff[7:0]};
    wire [5:0] compare_offset = request_word ^ {5'd0, second_due};
    // HS: count[31:24], flags[23:20] = complete/protocol/mismatch/seen,
    // marker A[19:16], first bad byte offset[15:8], its differing byte
    // lanes[7:4], bit 0 set when that DWORD was the companion beat.
    assign diagnostic = {checked_pairs, &seen_lines, protocol_error,
                         mismatch, |checked_pairs, 4'ha, bad_offset, 2'b00,
                         bad_lanes, 3'b000, bad_second};

    always @(posedge clk) begin
        second_due <= 0;
        if (!enable) begin
            pending <= 0;
            in_header <= 0;
            second_due <= 0;
            request_word <= 0;
            seen_lines <= 0;
            checked_pairs <= 0;
            mismatch <= 0;
            protocol_error <= 0;
            bad_offset <= 0;
            bad_lanes <= 0;
            bad_second <= 0;
        end else begin
            if (second_due) begin
                seen_lines[request_word[5:1]] <= 1'b1;
                if (checked_pairs != 8'hff) checked_pairs <= checked_pairs + 1'b1;
            end
            if (rd_ready) begin
                if (!pending || second_due) protocol_error <= 1;
                pending <= 0;
                if (pending && in_header && !second_due) begin
                    second_due <= 1;
                end
            end
            if (compare_valid && !mismatch && |compare_lanes) begin
                mismatch <= 1;
                bad_offset <= compare_offset;
                bad_lanes <= compare_lanes;
                bad_second <= second_due;
            end
            if (rd_req) begin
                if (pending && !rd_ready) protocol_error <= 1;
                // A new request on the first response edge would overwrite
                // metadata still needed by its companion DWORD. Flag it.
                if (rd_ready) protocol_error <= 1;
                pending <= 1;
                in_header <= rd_addr < 25'd48;
                request_word <= rd_addr[5:0];
            end
        end
    end
endmodule
`default_nettype wire
