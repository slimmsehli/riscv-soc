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
        do begin rd(4, s); cycles = cycles + 1; if (cycles > 300) $fatal(1, "I2C command timeout status=%x state=%0d", s, dut.state); end
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
    logic [31:0] rng_state = 32'h1;
    integer write_cov [0:3];
    task automatic random_byte(output logic [7:0] value);
        rng_state = rng_state ^ (rng_state << 13);
        rng_state = rng_state ^ (rng_state >> 17);
        rng_state = rng_state ^ (rng_state << 5);
        value = rng_state[7:0];
    endtask

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
        logic [7:0] random_data;
        for (integer k=0; k<4; k=k+1) write_cov[k]=0;
        if ($value$plusargs("SEED=%d", rng_state)) begin end
        if (rng_state == 0) rng_state=32'h1;
        repeat (4) @(negedge clk); rst_n = 1;
        $display("I2C seed=%0d scenario: divider reset, START, WRITE, ACK, STOP", rng_state);
        rd(8, received);
        if (received != 250) $fatal(1, "bad I2C divider reset");
        wr(8, 4);
        $display("I2C boundary: reset while START command is active");
        wr(4, 1);
        wait (dut.busy);
        rst_n=0; repeat (3) @(negedge clk);
        if (scl_low || sda_low) $fatal(1, "I2C did not release lines during reset");
        rst_n=1; repeat (3) @(negedge clk);
        rd(4, status);
        if (status[1:0] != 0) $fatal(1, "I2C command state survived reset: %x", status);
        wr(8, 4); // reset restores the slow default divider
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

        $display("I2C scenario: data pattern sweep");
        for (integer n=0; n<4; n=n+1) begin
            logic [7:0] pattern;
            case (n)
                0: pattern=8'h00;
                1: pattern=8'hff;
                2: pattern=8'hc3;
                default: pattern=8'h96;
            endcase
            wr(0, pattern);
            bit_count=0; observed=0;
            command(4);
            if (observed != pattern) $fatal(1, "write pattern %02x observed %02x", pattern, observed);
            $display("  I2C target captured=%02x", observed);
        end

        $display("I2C scenario: seeded random byte transfers");
        for (integer n=0; n<32; n=n+1) begin
            random_byte(random_data);
            wr(0, random_data);
            bit_count=0; observed=0;
            command(4);
            if (observed != random_data)
                $fatal(1, "seed=%0d I2C random[%0d] expected=%02x got=%02x", rng_state,n,random_data,observed);
            write_cov[random_data[7:6]]++;
        end
        for (integer k=0; k<4; k=k+1)
            if (write_cov[k] == 0) $fatal(1, "seed=%0d I2C write coverage bin %0d empty", rng_state,k);
        $display("  I2C write coverage value[7:6] bins=%0d,%0d,%0d,%0d",
            write_cov[0],write_cov[1],write_cov[2],write_cov[3]);

        $display("I2C scenario: target READ byte and controller NACK");
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
        wr(4, 1 << 9);
        rd(4, status);
        if (status[2]) $fatal(1, "ACK error W1C failed");

        $display("I2C scenario: clock stretch, invalid command, disabled controller, status clear");
        // SCL held low by the target must pause a high phase, then recover.
        target_ack = 1; stretching = 1; target_scl_low = 1;
        fork begin repeat (10) @(posedge clk); target_scl_low = 0; end join_none
        command(1); command(2); stretching = 0;

        wr(4, 5); // simultaneous START and WRITE is unsupported
        rd(4, status);
        if (!status[2] || status[0]) $fatal(1, "overlapping command status incorrect %x", status);
        wr(4, 1 << 9); rd(4, status);
        if (status[2]) $fatal(1, "overlap error clear failed");

        wr(8, 1); rd(8, received);
        if (received != 4) $fatal(1, "divider minimum clamp failed: %0d", received);

        wr(12, 0); // disabled controller rejects commands cleanly
        wr(4, 1);
        rd(4, status);
        if (!status[2] || status[0]) $fatal(1, "disabled command status incorrect %x", status);
        $display("I2C_TEST_PASS");
        $finish;
    end

    initial begin #1000000; $fatal(1, "I2C test timeout"); end
endmodule
