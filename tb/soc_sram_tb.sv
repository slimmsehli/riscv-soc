`timescale 1ns/1ps
module soc_sram_tb;
    logic clk = 0;
    always #5 clk = ~clk;
    logic valid = 0, write = 0;
    logic [31:0] addr = 0, wdata = 0;
    logic [3:0] wstrb = 0;
    wire ready, error;
    wire [31:0] rdata;
    soc_sram #(.WORDS(4), .INIT_FILE("tb/sram_init.hex")) dut
        (.clk, .rst_n(1'b1), .valid, .ready, .addr, .write, .wdata, .wstrb, .rdata, .error);

    task automatic read_word(input logic [31:0] a, input logic [31:0] expected);
        @(negedge clk); valid=1; write=0; addr=a; #1;
        if (!ready || error || rdata != expected)
            $fatal(1, "SRAM read %08x got %08x expected %08x error=%b", a, rdata, expected, error);
        @(posedge clk); #1; @(negedge clk); valid=0;
    endtask

    initial begin
        read_word(0, 32'h11223344);
        read_word(4, 32'haabbccdd);
        @(negedge clk); valid=1; write=1; addr=0; wdata=32'h0000ee00; wstrb=4'b0010;
        @(posedge clk); #1; @(negedge clk); valid=0; write=0;
        read_word(0, 32'h1122ee44);
        @(negedge clk); valid=1; addr=1; write=0; #1;
        if (!error || !ready) $fatal(1, "unaligned SRAM request did not error");
        @(posedge clk); #1; @(negedge clk); valid=0;
        @(negedge clk); valid=1; addr=16; write=0; #1;
        if (!error || !ready) $fatal(1, "out-of-range SRAM request did not error");
        $display("SOC_SRAM_PASS");
        $finish;
    end
    initial begin #1000; $fatal(1, "SRAM test timeout"); end
endmodule
