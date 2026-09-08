`default_nettype none

// Capture the four diagnostic words together when the APF menu opens.
// The payload is held in clk_sys from request acceptance until a later
// request. Only request/acknowledgment toggles cross synchronizers: by the
// time the host observes ack, the bundled payload has settled for two host
// clocks. A second menu entry during the handshake is retained as pending.
// No game reset input: diagnostics must remain available during a reset stall.
module cart_debug_snapshot (
    input  wire         clk_host,
    input  wire         clk_sys,
    input  wire         host_menu,
    input  wire [127:0] sys_debug,
    output reg  [127:0] host_debug = 128'd0
);
    reg menu_previous = 1'b0;
    reg request_toggle = 1'b0;
    reg ack_seen = 1'b0;
    reg pending = 1'b0;
    reg ack_toggle = 1'b0;
    reg [127:0] captured_debug = 128'd0;

    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg [1:0] request_sync = 2'b00;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg [1:0] ack_sync = 2'b00;

    wire menu_entry = host_menu && !menu_previous;
    wire busy = request_toggle != ack_seen;

    always @(posedge clk_sys) begin
        request_sync <= {request_sync[0], request_toggle};
        if (request_sync[1] != ack_toggle) begin
            captured_debug <= sys_debug;
            ack_toggle <= request_sync[1];
        end
    end

    always @(posedge clk_host) begin
        menu_previous <= host_menu;
        ack_sync <= {ack_sync[0], ack_toggle};

        if (ack_sync[1] != ack_seen) begin
            host_debug <= captured_debug;
            ack_seen <= ack_sync[1];
            if (pending || menu_entry) begin
                request_toggle <= !request_toggle;
                pending <= 1'b0;
            end
        end else if (!busy && menu_entry) begin
            request_toggle <= !request_toggle;
        end else if (busy && menu_entry) begin
            pending <= 1'b1;
        end
    end
endmodule

`default_nettype wire
