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
    output wire [63:0] diagnostic
);
    function [63:0] reference_pair(input [4:0] line_addr);
        case (line_addr)
            5'd0: reference_pair = 64'h51aeff24ea00002e;
            5'd1: reference_pair = 64'h0a82843d21a29a69;
            5'd2: reference_pair = 64'h988b2411ad09e484;
            5'd3: reference_pair = 64'h19be52a3217f81c0;
            5'd4: reference_pair = 64'h4a4a461020ce0993;
            5'd5: reference_pair = 64'h33e8c758ec3127f8;
            5'd6: reference_pair = 64'h94dff485bfcee382;
            5'd7: reference_pair = 64'hc08a5694c1094bce;
            5'd8: reference_pair = 64'h734d849ffca77213;
            5'd9: reference_pair = 64'h27a39758619acaa3;
            5'd10: reference_pair = 64'h61c71d23769803fc;
            5'd11: reference_pair = 64'h008438bf56ae0403;
            5'd12: reference_pair = 64'h03fe52fffd0ea740;
            5'd13: reference_pair = 64'h85c0fb97f130956f;
            5'd14: reference_pair = 64'h03be63a92580d660;
            5'd15: reference_pair = 64'hff34a2f9e2384e01;
            5'd16: reference_pair = 64'hcb90007844033ebb;
            5'd17: reference_pair = 64'h637cc065943a1188;
            5'd18: reference_pair = 64'h8be425d6af3cf087;
            5'd19: reference_pair = 64'h07f8d42172ac0a38;
            5'd20: reference_pair = 64'h5353494d4f52455a;
            5'd21: reference_pair = 64'h45584d42454e4f49;
            5'd22: reference_pair = 64'h0000000000963130;
            5'd23: reference_pair = 64'h00001d0000000000;
            default: reference_pair = 64'd0;
        endcase
    endfunction

    reg pending = 0, in_header = 0, second_due = 0;
    reg [5:0] request_word = 0;
    reg [63:0] expected_pair = 0;
    reg [23:0] seen_lines = 0;
    reg [15:0] checked_pairs = 0;
    reg mismatch = 0, protocol_error = 0;
    reg [5:0] bad_offset = 0; // DWORD offset, exported as byte offset
    reg [31:0] bad_word = 0;
    wire [31:0] expected_first = request_word[0] ? expected_pair[63:32] : expected_pair[31:0];
    wire [31:0] expected_second = request_word[0] ? expected_pair[31:0] : expected_pair[63:32];
    // HS: count[31:16], flags[15:12] = complete/protocol/mismatch/seen,
    // marker A[11:8], first bad byte offset[7:0]. HD: first bad DWORD.
    assign diagnostic = {checked_pairs, &seen_lines, protocol_error,
                         mismatch, |checked_pairs, 4'ha, bad_offset, 2'b00, bad_word};

    always @(posedge clk) begin
        second_due <= 0;
        if (!enable) begin
            pending <= 0;
            in_header <= 0;
            second_due <= 0;
            request_word <= 0;
            expected_pair <= 0;
            seen_lines <= 0;
            checked_pairs <= 0;
            mismatch <= 0;
            protocol_error <= 0;
            bad_offset <= 0;
            bad_word <= 0;
        end else begin
            if (second_due) begin
                seen_lines[request_word[5:1]] <= 1'b1;
                if (checked_pairs != 16'hffff) checked_pairs <= checked_pairs + 1'b1;
                if (!mismatch && rd_data_second != expected_second) begin
                    mismatch <= 1;
                    bad_offset <= request_word ^ 6'd1;
                    bad_word <= rd_data_second;
                end
            end
            if (rd_ready) begin
                if (!pending || second_due) protocol_error <= 1;
                pending <= 0;
                if (pending && in_header && !second_due) begin
                    second_due <= 1;
                    if (!mismatch && rd_data != expected_first) begin
                        mismatch <= 1;
                        bad_offset <= request_word;
                        bad_word <= rd_data;
                    end
                end
            end
            if (rd_req) begin
                if (pending && !rd_ready) protocol_error <= 1;
                // A new request on the first response edge would overwrite
                // metadata still needed by its companion DWORD. Flag it.
                if (rd_ready) protocol_error <= 1;
                pending <= 1;
                in_header <= rd_addr < 25'd48;
                request_word <= rd_addr[5:0];
                expected_pair <= reference_pair(rd_addr[5:1]);
            end
        end
    end
endmodule
`default_nettype wire
