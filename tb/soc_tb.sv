`timescale 1ns/1ps
module soc_tb;
    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    logic uart_rx = 1;
    wire uart_tx;
    tri1 i2c_scl, i2c_sda;
    logic target_sda_low = 0, target_scl_low = 0;
    logic target_read_mode = 0, target_write_mode = 0;
    logic [3:0] target_bit = 0;
    logic [7:0] target_written = 0;
    logic [7:0] target_read_value = 8'ha5;
    logic [7:0] uart_bytes [0:63];
    integer uart_count = 0;
    integer i2c_start_count = 0, i2c_stop_count = 0, i2c_read_bits = 0;
    logic [31:0] completion = 0;
    integer cycles = 0;

    assign i2c_scl = target_scl_low ? 1'b0 : 1'bz;
    assign i2c_sda = target_sda_low ? 1'b0 : 1'bz;

    soc_top #(.SRAM_INIT_FILE("build/soc_test.hex")) dut(
        .clk, .rst_n, .uart_rx, .uart_tx, .i2c_scl, .i2c_sda, .cpu_trap()
    );

    // Capture UART output independently from the transmitter register path.
    initial forever begin
        @(negedge uart_tx);
        if (rst_n) begin
            repeat (24) @(posedge clk);
            for (integer b = 0; b < 8; b = b + 1) begin
                uart_bytes[uart_count][b] = uart_tx;
                repeat (16) @(posedge clk);
            end
            if (uart_tx !== 1'b1) $fatal(1, "UART stop bit was low");
            uart_count = uart_count + 1;
        end
    end

    // Testbench target supports the integration program's byte write and byte read.
    always @(posedge clk) begin
        if (dut.i2c_valid && dut.i2c_ready && dut.i2c_write && dut.i2c_addr == 4'h4) begin
            if (dut.i2c_wdata[3]) begin
                target_read_mode <= 1;
                target_write_mode <= 0;
                target_bit <= 0;
                target_sda_low <= ~target_read_value[7];
            end else if (dut.i2c_wdata[2]) begin
                target_write_mode <= 1;
                target_read_mode <= 0;
                target_bit <= 0;
                target_written <= 0;
                target_sda_low <= 0;
            end else if (dut.i2c_wdata[1]) begin
                target_read_mode <= 0;
                target_write_mode <= 0;
                target_sda_low <= 0;
            end else if (dut.i2c_wdata[0]) begin
                target_read_mode <= 0;
                target_write_mode <= 0;
                target_sda_low <= 0;
            end
        end
        if (rst_n && dut.cpu_valid && dut.cpu_ready && dut.cpu_write && dut.cpu_addr == 32'h10003000)
            completion <= dut.cpu_wdata;
        cycles <= cycles + 1;
    end

    always @(posedge i2c_scl) begin
        if (rst_n && target_write_mode && target_bit < 8) begin
            target_written <= {target_written[6:0], i2c_sda};
            target_bit <= target_bit + 1'b1;
        end else if (rst_n && target_read_mode && target_bit < 8) begin
            target_bit <= target_bit + 1'b1;
            i2c_read_bits <= i2c_read_bits + 1;
        end else if (rst_n && target_bit == 8) target_bit <= 9;
    end
    always @(negedge i2c_sda) if (rst_n && i2c_scl) i2c_start_count <= i2c_start_count + 1;
    always @(posedge i2c_sda) if (rst_n && i2c_scl) i2c_stop_count <= i2c_stop_count + 1;
    always @(negedge i2c_scl) begin
        if (rst_n && target_write_mode && target_bit == 8) target_sda_low <= 1;
        else if (rst_n && target_bit == 9) begin
            target_sda_low <= 0;
            target_write_mode <= 0;
            target_bit <= 0;
        end else if (rst_n && target_read_mode && target_bit < 8)
            target_sda_low <= ~target_read_value[7-target_bit];
        else if (rst_n && target_read_mode && target_bit == 8)
            target_sda_low <= 0;
    end

    initial begin
        // The SRAM is loaded by soc_sram's $readmemh before reset is released.
        $display("SoC scenario: load RV32I image, release reset, wait for C firmware");
        repeat (5) @(negedge clk); rst_n = 1;
        while (completion == 0 && cycles < 2000000) @(negedge clk);
        if (completion != 32'h600d600d) $fatal(1, "software failure marker %08x", completion);
        $display("SoC firmware completed at cycle=%0d marker=%08x", cycles, completion);
        repeat (2000) @(negedge clk);
        $display("SoC scenario: independently validate UART stream, DMA SRAM, I2C pins");
        if (uart_count < 18) $fatal(1, "too few UART bytes captured: %0d", uart_count);
        if (uart_bytes[0] != "S" || uart_bytes[1] != "O" || uart_bytes[2] != "C" ||
            uart_bytes[3] != ":" || uart_bytes[4] != "U" || uart_bytes[5] != "A" ||
            uart_bytes[6] != "R" || uart_bytes[7] != "T" || uart_bytes[8] != 8'h0a ||
            uart_bytes[9] != "S" || uart_bytes[10] != "O" || uart_bytes[11] != "C" ||
            uart_bytes[12] != ":" || uart_bytes[13] != "P" || uart_bytes[14] != "A" ||
            uart_bytes[15] != "S" || uart_bytes[16] != "S" || uart_bytes[17] != 8'h0a)
            $fatal(1, "UART signature mismatch");
        if (target_written != 8'h5a) $fatal(1, "I2C target saw %02x", target_written);
        if (i2c_start_count < 2 || i2c_stop_count < 2 || i2c_read_bits != 8)
            $fatal(1, "I2C bus sequence incomplete starts=%0d stops=%0d read_bits=%0d",
                i2c_start_count, i2c_stop_count, i2c_read_bits);
        for (integer b = 0; b < 13; b = b + 1) begin
            logic [7:0] copied;
            copied = dut.sram.words[(32'h1103+b)>>2][((32'h1103+b)&3)*8 +: 8];
            if (copied != (8'h31 + b*7)) $fatal(1, "DMA memory byte %0d got %02x", b, copied);
        end
        if (dut.cpu_trap) $fatal(1, "CPU trapped");
        $display("SOC_TEST_PASS uart_bytes=%0d dma_bytes=13 i2c_starts=%0d i2c_stops=%0d",
            uart_count, i2c_start_count, i2c_stop_count);
        $finish;
    end
    initial begin #30000000; $fatal(1, "SoC testbench timeout"); end
endmodule
