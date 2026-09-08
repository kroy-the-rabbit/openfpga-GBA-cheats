`timescale 1ns/1ps
`default_nettype none

module tb_cart_debug_snapshot;
    reg clk_host = 0, clk_sys = 0, host_menu = 0;
    always #7 clk_host = !clk_host;
    always #11 clk_sys = !clk_sys;

    reg [31:0] epoch = 32'd1;
    wire [127:0] sys_debug = {epoch, ~epoch, epoch ^ 32'hA55AF00F, epoch + 32'd12345};
    wire [127:0] host_debug;
    cart_debug_snapshot dut(.*);

    reg [127:0] expected [0:15];
    reg [127:0] previous_debug = 0;
    integer captures = 0, publications = 0;
    always @(posedge clk_sys) begin
        epoch <= epoch + 1;
        if (dut.request_sync[1] != dut.ack_toggle) begin
            expected[captures] = sys_debug;
            captures = captures + 1;
        end
    end
    always @(negedge clk_host) begin
        if (host_debug !== previous_debug) begin
            if (publications >= captures || host_debug !== expected[publications])
                $fatal(1, "Snapshot was torn, reordered, or published before capture");
            publications = publications + 1;
            previous_debug = host_debug;
        end
    end

    task wait_publications(input integer wanted);
        integer timeout;
        begin
            timeout = 0;
            while (publications != wanted && timeout < 50) begin
                @(negedge clk_host); #1;
                timeout = timeout + 1;
            end
            if (publications != wanted) $fatal(1, "Snapshot handshake did not finish");
        end
    endtask

    initial begin
        repeat (5) @(negedge clk_host);
        #1;
        if (host_debug !== 128'd0 || captures != 0) $fatal(1, "Initial snapshot is not zero");
        host_menu = 1;
        wait_publications(1);
        repeat (20) @(negedge clk_host);
        #1;
        if (captures != 1 || publications != 1) $fatal(1, "Open menu repeatedly captured");

        host_menu = 0;
        repeat (3) @(negedge clk_host);
        #1; host_menu = 1;
        wait_publications(2);
        if (captures != 2) $fatal(1, "Later menu entry was not captured");

        host_menu = 0;
        repeat (3) @(negedge clk_host);
        #1; host_menu = 1;
        @(negedge clk_host); #1; host_menu = 0;
        @(negedge clk_host); #1;
        if (!dut.busy) $fatal(1, "Test did not exercise in-flight menu entry");
        host_menu = 1;
        wait_publications(4);
        repeat (20) @(negedge clk_host);
        #1;
        if (captures != 4 || publications != 4) $fatal(1, "In-flight menu entry was lost or duplicated");
        $display("PASS coherent asynchronous debug snapshots, menu stability and in-flight re-entry");
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "Watchdog expired");
    end
endmodule

`default_nettype wire
