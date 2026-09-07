// rom_source_mux.sv
//
// M1: selects where gba_top ROM reads come from:
//   cart_mode == 0 -> SDRAM (existing SD-ROM path, unchanged behavior)
//   cart_mode == 1 -> physical cartridge via gba_cart_controller
//
// Save-state staging reads (ss_serving_active) stay on SDRAM in the
// surrounding logic; this mux only handles the normal ROM-read path.

`default_nettype none

module rom_source_mux (
    input  wire        clk,
    input  wire        cart_mode,

    // from gba_top
    input  wire        gba_rd_req,
    input  wire [24:0] gba_rd_addr,

    // to gba_top
    output wire        gba_rd_ready,
    output wire [31:0] gba_rd_data,
    output wire [31:0] gba_rd_data_second,

    // to SDRAM controller
    output wire        sdram_rd_req,
    output wire [24:0] sdram_rd_addr,
    input  wire        sdram_rd_ready,
    input  wire [31:0] sdram_rd_data,
    input  wire [31:0] sdram_rd_data_second,

    // to cartridge controller
    output wire        cart_rd_req,
    output wire [24:0] cart_rd_addr,
    input  wire        cart_rd_ready,
    input  wire [31:0] cart_rd_data,
    input  wire [31:0] cart_rd_data_second
);

    // Forward the request to the selected source
    assign sdram_rd_req   = cart_mode ? 1'b0 : gba_rd_req;
    assign sdram_rd_addr  = gba_rd_addr;
    assign cart_rd_req    = cart_mode ? gba_rd_req : 1'b0;

    // cache.vhd fills one aligned 8-byte line per request. SDRAM's burst
    // wraps within that line: an odd DWORD address returns the upper DWORD
    // first, then the lower. The cart controller instead reads forward.
    // Fetch an aligned pair and reorder it to preserve the cache contract.
    assign cart_rd_addr   = {gba_rd_addr[24:1], 1'b0};
    reg cart_upper_first = 1'b0;
    always @(posedge clk) begin
        if (cart_rd_req)
            cart_upper_first <= gba_rd_addr[0];
    end

    wire [31:0] cart_first = cart_upper_first ? cart_rd_data_second : cart_rd_data;
    wire [31:0] cart_second = cart_upper_first ? cart_rd_data : cart_rd_data_second;

    // Return the selected source's response to gba_top
    assign gba_rd_ready        = cart_mode ? cart_rd_ready        : sdram_rd_ready;
    assign gba_rd_data         = cart_mode ? cart_first           : sdram_rd_data;
    assign gba_rd_data_second  = cart_mode ? cart_second          : sdram_rd_data_second;

endmodule

`default_nettype wire
