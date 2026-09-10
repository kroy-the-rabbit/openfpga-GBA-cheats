`default_nettype none

// Serial cartridge EEPROM request buffer.
// Every host bit is forwarded to the bus controller as it arrives; the
// bridge adds nothing to the protocol. What it keeps is the transfer
// lifetime: an interrupted physical WRITE cannot safely be restarted by
// pulsing CS#, so an abort in the middle of a transfer sets a fail-closed
// latch that blocks further EEPROM traffic until a controller reset.
//
// 2026-09-09: the read-only policy, which forwarded only DMA3 read commands
// of 9 or 17 bits with a verified 11 prefix, was removed. Zero Mission's
// save request does not fit that shape, so every read came back as ones and
// the game showed no saves. With raw forwarding it reads and writes, and
// Analogue's own cartridge mode reads the write back.
//
// The fault latch once had no clear at all, and that killed the whole save
// path: `fault` fed the condition that clears `transfer_open`, which feeds
// the abort, which sets `fault`. Quartus resolved that cycle to a constant
// and the fitted bridge was one ALM. `scripts/inspect_timing.tcl` fails a
// build where these registers do not survive.
module cart_eeprom_bridge (
    input  wire        clk,
    input  wire        reset_n,

    input  wire        host_req,
    input  wire        host_rnw,
    input  wire        host_din,
    input  wire        host_dma,
    // Channel lifetime, including gaps/preemption between individual bits.
    input  wire        host_dma_active,
    input  wire [16:0] host_count,
    input  wire        host_last,
    output reg         host_dout,
    output reg         host_done,

    output reg         ctl_req,
    output reg         ctl_rnw,
    output reg         ctl_din,
    output reg         ctl_dma,
    input  wire        ctl_dout,
    input  wire        ctl_done,

    output wire        fault,
    // Why the latch fired, sampled on that clock and held. Marker E in
    // 31:28, FSM state 27:26, then dma_active dropped, reset_n dropped,
    // transfer_sent, ctl_req, reserved, host_rnw, transfer_open, reserved,
    // host_dma, host_req, and the host's bit index in 15:0.
    output wire [31:0] fault_why
);
    // Power-up values live on internal registers driven out through wires;
    // an initialiser on a port declaration is not reliably honoured.
    reg        fault_r     = 1'b0;
    reg [31:0] fault_why_r = 32'd0;
    assign fault     = fault_r;
    assign fault_why = fault_why_r;

    localparam IDLE     = 2'd0;
    localparam WAIT_BIT = 2'd1;
    reg [1:0] state = IDLE;
    reg       host_last_r = 1'b1;
    reg       transfer_open = 1'b0;
    reg       transfer_sent = 1'b0;

    // ctl_req is the request accepted by the outer queue on this edge. Count
    // it even if DMA/reset changes simultaneously: the accepted bit may drain.
    wire abort_condition = transfer_open && (transfer_sent || ctl_req) &&
                           (!host_dma_active || !reset_n) &&
                           !(host_done && host_last_r);

    // The reset is synchronous so the first reset clock can record a live
    // physical transfer before clearing the FSM. The bus controller owns the
    // electrical pulse and finishes it on its own.
    always @(posedge clk) begin
        if (abort_condition && fault_why_r == 32'd0) begin
            fault_why_r <= {4'hE, state, !host_dma_active, !reset_n,
                            transfer_sent, ctl_req, 1'b0, host_rnw,
                            transfer_open, 1'b0, host_dma, host_req,
                            host_count[15:0]};
        end
        if (abort_condition) fault_r <= 1'b1;

        // `fault` deliberately does not appear here; see the header.
        if (!reset_n || !host_dma_active || abort_condition) begin
            transfer_open <= 1'b0;
            transfer_sent <= 1'b0;
        end else begin
            if (host_done && host_last_r) begin
                // The last physical bit has completed, not merely queued.
                transfer_open <= 1'b0;
                transfer_sent <= 1'b0;
            end
            if (state == IDLE && host_req && host_dma &&
                (!transfer_open || (host_done && host_last_r))) begin
                transfer_open <= 1'b1;
                transfer_sent <= 1'b0;
            end
            if (ctl_req) transfer_sent <= 1'b1;
        end

        if (!reset_n) begin
            state       <= IDLE;
            host_last_r <= 1'b1;
            host_dout   <= 1'b1;
            host_done   <= 1'b0;
            ctl_req     <= 1'b0;
            ctl_rnw     <= 1'b1;
            ctl_din     <= 1'b0;
            ctl_dma     <= 1'b0;
        end else begin
            host_done <= 1'b0;
            ctl_req   <= 1'b0;
            if (fault_r || abort_condition) begin
                // Retire the accepted bit immediately instead of waiting on
                // ctl_done: cart_bus_arbiter only forwards that done while
                // EEPROM is the active master, so waiting can hang
                // gba_memorymux's CART_EEPROM_WAIT forever. No new ctl_req
                // is issued once faulted; the host reads ones.
                host_dout <= 1'b1;
                case (state)
                    WAIT_BIT: begin
                        host_done <= 1'b1;
                        state     <= IDLE;
                    end
                    default: if (host_req) host_done <= 1'b1;
                endcase
            end else case (state)
                IDLE: if (host_req) begin
                    host_last_r <= host_last;
                    if (host_dma && !host_dma_active) begin
                        // The memory bus may retire a bit after DMA aborts.
                        host_dout <= 1'b1;
                        host_done <= 1'b1;
                    end else begin
                        ctl_req <= 1'b1;
                        ctl_rnw <= host_rnw;
                        ctl_din <= host_rnw ? 1'b0 : host_din;
                        ctl_dma <= host_dma && !host_last;
                        state   <= WAIT_BIT;
                    end
                end

                WAIT_BIT: if (ctl_done) begin
                    host_dout <= ctl_dout;
                    host_done <= 1'b1;
                    state     <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
