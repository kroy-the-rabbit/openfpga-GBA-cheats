// One outstanding request per client, matching the cache and memorymux
// handshakes. Capture pulses even while another client owns the slot.
`default_nettype none
module cart_bus_arbiter (
    input wire clk, reset_n,
    input wire probe_req,
    input wire [24:0] probe_addr,
    output wire probe_done,
    input wire rom_req,
    input wire [24:0] rom_addr,
    output wire rom_done,
    input wire save_req,
    input wire [16:0] save_addr,
    input wire save_rnw,
    input wire [7:0] save_din,
    output wire save_done,
    input wire ee_req, ee_rnw, ee_din, ee_dma,
    output wire ee_done,
    output reg ctl_rom_req,
    output reg [24:0] ctl_rom_addr,
    input wire ctl_rom_done,
    output reg ctl_save_req,
    output reg [16:0] ctl_save_addr,
    output reg ctl_save_rnw,
    output reg [7:0] ctl_save_din,
    input wire ctl_save_done,
    output reg ctl_ee_req, ctl_ee_rnw, ctl_ee_din, ctl_ee_dma,
    input wire ctl_ee_done,
    output wire busy
);
    localparam IDLE=2'd0, ROM=2'd1, SAVE=2'd2, EEPROM=2'd3;
    reg [1:0] active;
    reg active_probe;
    reg probe_prev;
    reg p_rom, p_probe, p_save, p_ee;
    reg [24:0] rom_addr_q;
    reg [16:0] save_addr_q;
    reg save_rnw_q;
    reg [7:0] save_din_q;
    reg ee_rnw_q, ee_din_q, ee_dma_q;

    // The probe holds its request until completion. The CPU is held in
    // reset during probing, so it shares the ROM queue without contention.
    wire probe_pulse = probe_req && !probe_prev;
    assign probe_done = active == ROM && active_probe && ctl_rom_done;
    assign rom_done = active == ROM && !active_probe && ctl_rom_done;
    assign save_done = active == SAVE && ctl_save_done;
    assign ee_done = active == EEPROM && ctl_ee_done;
    assign busy = active != IDLE || p_rom || p_save || p_ee;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            active <= IDLE;
            active_probe <= 0;
            probe_prev <= 0;
            p_rom <= 0; p_probe <= 0; p_save <= 0; p_ee <= 0;
            rom_addr_q <= 0; save_addr_q <= 0; save_rnw_q <= 1;
            save_din_q <= 0; ee_rnw_q <= 1; ee_din_q <= 0; ee_dma_q <= 0;
            ctl_rom_req <= 0; ctl_save_req <= 0; ctl_ee_req <= 0;
            ctl_rom_addr <= 0; ctl_save_addr <= 0;
            ctl_save_rnw <= 1; ctl_save_din <= 0;
            ctl_ee_rnw <= 1; ctl_ee_din <= 0; ctl_ee_dma <= 0;
        end else begin
            probe_prev <= probe_req;
            ctl_rom_req <= 0; ctl_save_req <= 0; ctl_ee_req <= 0;
            if (probe_pulse || rom_req) begin
                p_rom <= 1;
                p_probe <= probe_pulse;
                rom_addr_q <= probe_pulse ? probe_addr : rom_addr;
            end
            if (save_req) begin
                p_save <= 1;
                save_addr_q <= save_addr;
                save_rnw_q <= save_rnw;
                save_din_q <= save_din;
            end
            if (ee_req) begin
                p_ee <= 1;
                ee_rnw_q <= ee_rnw; ee_din_q <= ee_din; ee_dma_q <= ee_dma;
            end
            case (active)
                IDLE: begin
                    // Finish EEPROM bits promptly to preserve the serial
                    // session. Each client waits for its response before
                    // issuing another request, so queued ROM reads progress.
                    if (p_ee) begin
                        p_ee <= 0;
                        active <= EEPROM;
                        ctl_ee_rnw <= ee_rnw_q;
                        ctl_ee_din <= ee_din_q;
                        ctl_ee_dma <= ee_dma_q;
                        ctl_ee_req <= 1;
                    end else if (p_save) begin
                        p_save <= 0;
                        active <= SAVE;
                        ctl_save_addr <= save_addr_q;
                        ctl_save_rnw <= save_rnw_q;
                        ctl_save_din <= save_din_q;
                        ctl_save_req <= 1;
                    end else if (p_rom) begin
                        p_rom <= 0;
                        active <= ROM;
                        active_probe <= p_probe;
                        ctl_rom_addr <= rom_addr_q;
                        ctl_rom_req <= 1;
                    end
                end
                ROM: if (ctl_rom_done) active <= IDLE;
                SAVE: if (ctl_save_done) active <= IDLE;
                EEPROM: if (ctl_ee_done) active <= IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
