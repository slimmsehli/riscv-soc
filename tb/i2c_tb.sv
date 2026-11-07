`timescale 1ns/1ps
module i2c_tb;
    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    logic cfg_valid = 0, cfg_write = 0;
    logic [3:0] cfg_addr = 0, cfg_wstrb = 0;
    logic [31:0] cfg_wdata = 0;
    wire cfg_ready, cfg_error, scl_low, sda_low;
    wire [31:0] cfg_rdata;
    wire scl, sda;
    logic target_sda_low = 0, target_scl_low = 0;
    logic stretching = 0;
    assign scl = !(scl_low || target_scl_low);
    assign sda = !(sda_low || target_sda_low);

    i2c_master dut(.clk, .rst_n, .cfg_valid, .cfg_ready, .cfg_addr, .cfg_write,
        .cfg_wdata, .cfg_wstrb, .cfg_rdata, .cfg_error,
        .i2c_scl_in(scl), .i2c_scl_low(scl_low), .i2c_sda_in(sda), .i2c_sda_low(sda_low));

    task automatic wr(input logic [3:0] a, input logic [31:0] d);
        @(negedge clk); cfg_valid = 1; cfg_write = 1; cfg_addr = a; cfg_wdata = d; cfg_wstrb = 15;
        @(posedge clk); #1;
        if (!cfg_ready || cfg_error) $fatal(1, "I2C config write error at %x", a);
        @(negedge clk); cfg_valid = 0; cfg_write = 0; cfg_wstrb = 0;
    endtask

    task automatic rd(input logic [3:0] a, output logic [31:0] d);
        @(negedge clk); cfg_valid = 1; cfg_write = 0; cfg_addr = a; #1;
        if (!cfg_ready || cfg_error) $fatal(1, "I2C config read error at %x", a);
        d = cfg_rdata;
        @(posedge clk); #1;
        @(negedge clk); cfg_valid = 0;
    endtask

    task automatic command(input logic [31:0] cmd);
        logic [31:0] s;
        integer cycles;
        wr(4, cmd);
        cycles = 0;
        do begin rd(4, s); cycles = cycles + 1; if (cycles > 300) $fatal(1, "I2C command timeout"); end
        while (s[0]);
        if (!s[1]) $fatal(1, "I2C command missing DONE");
    endtask

    logic [7:0] observed = 0;
    integer bit_count = 0;
    logic target_ack = 1;
    logic read_mode = 0;
    integer read_bit = 0;
    logic [7:0] target_byte = 8'hA5;
    logic [31:0] status, received;

    // Minimal behavioral target: capture a written byte, ACK its ninth clock,
    // and optionally drive a fixed byte during a controller read.
    always @(posedge scl) begin
        if (rst_n && read_mode && bit_count < 8) begin
            observed <= {observed[6:0], sda};
            bit_count <= bit_count + 1;
        end else if (rst_n && !read_mode && bit_count < 8) begin
            observed <= {observed[6:0], sda};
            bit_count <= bit_count + 1;
        end else if (rst_n && bit_count == 8) bit_count <= 9;
    end
    always @(negedge scl) begin
        if (rst_n && bit_count == 8 && target_ack) target_sda_low <= 1;
        else if (rst_n && bit_count == 9) begin
            target_sda_low <= 0;
            bit_count <= 0;
        end else if (rst_n && read_mode && bit_count < 8) begin
            target_sda_low <= ~target_byte[7-read_bit];
            read_bit <= read_bit + 1;
        end
    end
    initial begin
        repeat (4) @(negedge clk); rst_n = 1;
        rd(8, received);
        if (received != 250) $fatal(1, "bad I2C divider reset");
        wr(8, 4);
        command(1); // START
        if (sda !== 0 || scl !== 1) $fatal(1, "START condition not generated");
        wr(0, 8'h5a);
        bit_count = 0; observed = 0; read_mode = 0;
        command(4); // WRITE
        if (observed != 8'h5a) $fatal(1, "write byte mismatch %x", observed);
        rd(4, status);
        if (status[2]) $fatal(1, "ACK incorrectly reported as error");
        command(2); // STOP
        if (sda !== 1 || scl !== 1) $fatal(1, "STOP did not release bus");

        // Read a byte from the target and send NACK on the ninth clock.
        command(1);
        bit_count = 0; read_bit = 0; read_mode = 1; target_sda_low = 0;
        command(8); 
        read_mode = 0; target_sda_low = 0;
        rd(0, received);
        if (received[7:0] != target_byte) $fatal(1, "read data mismatch got=%x", received[7:0]);
        command(2);

        target_ack = 0;
        command(4);
        rd(4, status);
        if (!status[2]) $fatal(1, "NACK not reported");
        wr(4, 4);
        rd(4, status);
        if (status[2]) $fatal(1, "ACK error W1C failed");

        // SCL held low by the target must pause a high phase, then recover.
        target_ack = 1; stretching = 1; target_scl_low = 1;
        fork begin repeat (3) @(posedge clk); target_scl_low = 0; end join_none
        command(1); command(2); stretching = 0;

        wr(12, 0); // disabled controller rejects commands cleanly
        wr(4, 1);
        rd(4, status);
        if (!status[2] || status[0]) $fatal(1, "disabled command status incorrect %x", status);
        $display("I2C_TEST_PASS");
        $finish;
    end

    initial begin #1000000; $fatal(1, "I2C test timeout"); end
endmodule
