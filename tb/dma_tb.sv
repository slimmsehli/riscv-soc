`timescale 1ns/1ps
module dma_tb;
    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    logic cfg_valid = 0, cfg_write = 0;
    logic [3:0] cfg_addr = 0, cfg_wstrb = 0;
    logic [31:0] cfg_wdata = 0;
    wire cfg_ready, cfg_error;
    wire [31:0] cfg_rdata;
    wire dma_valid, dma_write;
    wire [31:0] dma_addr, dma_wdata;
    wire [3:0] dma_wstrb;
    logic dma_ready = 0, dma_error = 0;
    logic [31:0] dma_rdata = 0;

    logic cpu_valid = 0, cpu_write = 0;
    logic [31:0] cpu_addr = 0, cpu_wdata = 0;
    wire cpu_ready;
    logic [31:0] mem [0:255];
    logic prefer_cpu = 0;
    wire grant_cpu = cpu_valid && (!dma_valid || prefer_cpu);
    wire grant_dma = dma_valid && !grant_cpu;
    assign cpu_ready = grant_cpu;

    dma_ip dut(.clk, .rst_n, .cfg_valid, .cfg_ready, .cfg_addr, .cfg_write,
        .cfg_wdata, .cfg_wstrb, .cfg_rdata, .cfg_error,
        .mem_valid(dma_valid), .mem_ready(dma_ready), .mem_addr(dma_addr),
        .mem_write(dma_write), .mem_wdata(dma_wdata), .mem_wstrb(dma_wstrb),
        .mem_rdata(dma_rdata), .mem_error(dma_error));

    always_comb begin
        dma_ready = grant_dma;
        dma_error = 0;
        dma_rdata = 0;
        if (grant_dma) begin
            dma_rdata = mem[dma_addr[9:2]];
            if (inject_error && dma_write && dma_addr == error_addr) dma_error = 1;
        end
    end

    logic inject_error = 0;
    logic [31:0] error_addr = 0;
    integer cpu_grants = 0;
    always_ff @(posedge clk) begin
        if (grant_cpu) begin cpu_grants <= cpu_grants + 1; prefer_cpu <= 0; end
        else if (grant_dma) prefer_cpu <= 1;
        if (grant_dma && dma_write && !dma_error)
            for (integer lane = 0; lane < 4; lane = lane + 1)
                if (dma_wstrb[lane]) mem[dma_addr[9:2]][lane*8 +: 8] <= dma_wdata[lane*8 +: 8];
        if (grant_cpu && cpu_write) mem[cpu_addr[9:2]] <= cpu_wdata;
    end

    task automatic cfg_wr(input logic [3:0] a, input logic [31:0] d);
        @(negedge clk); cfg_valid = 1; cfg_write = 1; cfg_addr = a; cfg_wdata = d; cfg_wstrb = 15;
        @(posedge clk); #1;
        if (!cfg_ready || cfg_error) $fatal(1, "CSR write error at %x", a);
        @(negedge clk); cfg_valid = 0; cfg_write = 0; cfg_wstrb = 0;
    endtask

    task automatic cfg_rd(input logic [3:0] a, output logic [31:0] d);
        @(negedge clk); cfg_valid = 1; cfg_write = 0; cfg_addr = a; #1;
        if (!cfg_ready || cfg_error) $fatal(1, "CSR read error at %x", a);
        d = cfg_rdata;
        @(posedge clk); #1;
        @(negedge clk); cfg_valid = 0;
    endtask

    task automatic start_copy(input logic [31:0] s, input logic [31:0] d, input logic [31:0] n);
        cfg_wr(0, s); cfg_wr(4, d); cfg_wr(8, n); cfg_wr(12, 1);
    endtask

    task automatic wait_done;
        logic [31:0] s;
        integer cycles;
        cycles = 0;
        do begin cfg_rd(12, s); cycles = cycles + 1; if (cycles > 200) $fatal(1, "DMA timeout"); end
        while (s[0]);
        if (!s[1]) $fatal(1, "DMA completed without DONE (%x)", s);
    endtask

    logic [31:0] status;
    initial begin
        for (integer i = 0; i < 256; i = i + 1) mem[i] = 32'hcafe0000 + i;
        repeat (4) @(negedge clk); rst_n = 1;

        // Zero-byte request completes immediately.
        cfg_wr(8, 0); cfg_wr(12, 1); cfg_rd(12, status);
        if (status != 2) $fatal(1, "zero length status %x", status);
        cfg_wr(12, 2);

        // Unaligned source and destination across word boundaries, with concurrent CPU traffic.
        cpu_valid = 1; cpu_write = 1; cpu_addr = 32'h200; cpu_wdata = 32'h12345678;
        start_copy(32'h41, 32'h83, 11);
        cfg_wr(12, 1); // start while busy sets ERROR
        wait_done();
        cpu_valid = 0;
        if (cpu_grants == 0) $fatal(1, "CPU did not progress under contention");
        for (integer b = 0; b < 11; b = b + 1) begin
            logic [7:0] got, expected;
            got = mem[(32'h83 + b) >> 2][((32'h83 + b) & 3)*8 +: 8];
            expected = mem[(32'h41 + b) >> 2][((32'h41 + b) & 3)*8 +: 8];
            // Source range is untouched by the destination range, so compare the seeded bytes.
            if (got != expected)
                $fatal(1, "copy byte %0d got %x expected-source %x", b, got, expected);
        end
        cfg_rd(12, status);
        if (!status[2]) $fatal(1, "busy START did not set ERROR");
        cfg_wr(12, 6);
        cfg_rd(12, status);
        if (status != 0) $fatal(1, "W1C status clear failed %x", status);

        // Single byte transfer and a memory-bus error on destination write.
        start_copy(32'h20, 32'h40, 1); wait_done();
        if (mem[16][0 +: 8] != mem[8][0 +: 8]) $fatal(1, "single byte copy failed");
        cfg_wr(12, 2);
        inject_error = 1; error_addr = 32'hc0;
        start_copy(32'h20, 32'hc0, 2);
        cfg_rd(12, status);
        while (status[0]) cfg_rd(12, status);
        if (!status[2] || status[1]) $fatal(1, "bus error status incorrect %x", status);
        $display("DMA_TEST_PASS cpu_grants=%0d", cpu_grants);
        $finish;
    end

    initial begin #100000; $fatal(1, "DMA test timeout"); end
endmodule
