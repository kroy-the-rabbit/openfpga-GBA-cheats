`default_nettype none

// Serial cartridge EEPROM policy and request buffer.
// Reading the EEPROM starts with WR# pulses carrying 11 + address + 0.
// Read-only mode therefore cannot simply disable WR#. Only DMA3 read-command
// lengths (9/17 bits) with a verified 11 prefix are forwarded. Both prefix
// bits are buffered before either reaches the chip: rejecting 10 after its
// first bit would leave the physical serial parser part-way into a command.
// The memory bus supplies actual DMA3 ownership and an explicit last bit.
module cart_eeprom_bridge (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        write_enable,

    input  wire        host_req,
    input  wire        host_rnw,
    input  wire        host_din,
    input  wire        host_dma,
    input  wire [16:0] host_count,
    input  wire        host_last,
    output reg         host_dout,
    output reg         host_done,

    output reg         ctl_req,
    output reg         ctl_rnw,
    output reg         ctl_din,
    output reg         ctl_dma,
    input  wire        ctl_dout,
    input  wire        ctl_done
);

    localparam [1:0] IDLE = 2'd0, WAIT_BIT = 2'd1,
                     WAIT_PREFIX = 2'd2, ISSUE_SECOND = 2'd3;
    reg [1:0] state;
    reg command_active;
    reg command_raw;
    reg command_allowed;
    reg prefix_pending;
    reg second_dma;

    wire read_command_length = host_count == 17'd9 || host_count == 17'd17;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state           <= IDLE;
            command_active  <= 1'b0;
            command_raw     <= 1'b0;
            command_allowed <= 1'b0;
            prefix_pending  <= 1'b0;
            second_dma      <= 1'b0;
            host_dout       <= 1'b1;
            host_done       <= 1'b0;
            ctl_req         <= 1'b0;
            ctl_rnw         <= 1'b1;
            ctl_din         <= 1'b0;
            ctl_dma         <= 1'b0;
        end else begin
            host_done <= 1'b0;
            ctl_req   <= 1'b0;
            case (state)
                IDLE: if (host_req) begin
                    if (host_rnw) begin
                        // Reads include DMA data bursts and individual CPU
                        // ready polls. Each CPU access closes its selection.
                        command_active <= 1'b0;
                        prefix_pending <= 1'b0;
                        ctl_req  <= 1'b1;
                        ctl_rnw  <= 1'b1;
                        ctl_din  <= 1'b0;
                        ctl_dma  <= host_dma && !host_last;
                        state    <= WAIT_BIT;
                    end else if (!command_active) begin
                        command_active  <= host_dma && !host_last;
                        command_raw     <= write_enable;
                        command_allowed <= host_dma && read_command_length &&
                                           host_din && !host_last;
                        prefix_pending  <= !write_enable && host_dma &&
                                           read_command_length && host_din && !host_last;
                        if (write_enable) begin
                            ctl_req <= 1'b1;
                            ctl_rnw <= 1'b0;
                            ctl_din <= host_din;
                            ctl_dma <= host_dma && !host_last;
                            state   <= WAIT_BIT;
                        end else begin
                            // Either a locally buffered first read-command
                            // bit, or denied traffic. Neither clocks the cart.
                            host_dout <= 1'b1;
                            host_done <= 1'b1;
                        end
                    end else begin
                        if (host_last || !host_dma)
                            command_active <= 1'b0;

                        if (command_raw) begin
                            // Permission is fixed at the start of a command.
                            // Toggling the menu must not cut a program burst.
                            ctl_req <= 1'b1;
                            ctl_rnw <= 1'b0;
                            ctl_din <= host_din;
                            ctl_dma <= host_dma && !host_last;
                            state   <= WAIT_BIT;
                        end else if (prefix_pending) begin
                            prefix_pending <= 1'b0;
                            if (host_dma && host_din && !host_last && read_command_length) begin
                                // Prefix 11 is now known. Replay the first
                                // bit, then this host bit, before acknowledging.
                                ctl_req    <= 1'b1;
                                ctl_rnw    <= 1'b0;
                                ctl_din    <= 1'b1;
                                ctl_dma    <= 1'b1;
                                second_dma <= host_dma && !host_last;
                                state      <= WAIT_PREFIX;
                            end else begin
                                command_allowed <= 1'b0;
                                host_dout <= 1'b1;
                                host_done <= 1'b1;
                            end
                        end else if (command_allowed && host_dma && read_command_length) begin
                            ctl_req <= 1'b1;
                            ctl_rnw <= 1'b0;
                            ctl_din <= host_din;
                            ctl_dma <= host_dma && !host_last;
                            state   <= WAIT_BIT;
                        end else begin
                            host_dout <= 1'b1;
                            host_done <= 1'b1;
                        end
                    end
                end

                WAIT_PREFIX: if (ctl_done) begin
                    // Insert an idle request cycle after completion so the
                    // controller cannot accept the replay while retiring bit1.
                    state <= ISSUE_SECOND;
                end

                ISSUE_SECOND: begin
                    ctl_req <= 1'b1;
                    ctl_rnw <= 1'b0;
                    ctl_din <= 1'b1;
                    ctl_dma <= second_dma;
                    state   <= WAIT_BIT;
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
