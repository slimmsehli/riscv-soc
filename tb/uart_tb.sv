`timescale 1ns/1ps
module uart_tb;
    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    logic valid = 0, write = 0;
    logic [3:0] addr = 0, wstrb = 0;
    logic [31:0] wdata = 0;
    wire ready, error, tx;
    wire [31:0] rdata;
    logic rx = 1;

    uart_ip dut(.clk, .rst_n, .bus_valid(valid), .bus_ready(ready), .bus_addr(addr),
        .bus_write(write), .bus_wdata(wdata), .bus_wstrb(wstrb), .bus_rdata(rdata),
        .bus_error(error), .uart_rx(rx), .uart_tx(tx));

    task automatic bus_write32(input logic [3:0] a, input logic [31:0] d);
        @(negedge clk); valid = 1; write = 1; addr = a; wdata = d; wstrb = 4'hf;
        @(posedge clk); #1;
        if (!ready || error) $fatal(1, "write bus failure at %x", a);
        @(negedge clk); valid = 0; write = 0; wstrb = 0;
    endtask

    task automatic bus_read32(input logic [3:0] a, output logic [31:0] d);
        @(negedge clk); valid = 1; write = 0; addr = a; wstrb = 0; #1;
        if (!ready || error) $fatal(1, "read bus failure at %x", a);
        d = rdata;
        @(posedge clk); #1;
        @(negedge clk); valid = 0;
    endtask

    task automatic send_rx(input logic [7:0] value, input logic stop_bit);
        integer i;
        rx = 0; repeat (8) @(negedge clk);
        for (i = 0; i < 8; i = i + 1) begin rx = value[i]; repeat (8) @(negedge clk); end
        rx = stop_bit; repeat (8) @(negedge clk); rx = 1; repeat (3) @(negedge clk);
    endtask

    logic [31:0] value, status;
    integer bitno;
    logic [31:0] rng_state = 32'h1;
    integer rx_cov [0:3];
    task automatic random_byte(output logic [7:0] b);
        rng_state = rng_state ^ (rng_state << 13);
        rng_state = rng_state ^ (rng_state >> 17);
        rng_state = rng_state ^ (rng_state << 5);
        b = rng_state[7:0];
    endtask
    initial begin
        for (integer k=0; k<4; k=k+1) rx_cov[k]=0;
        if ($value$plusargs("SEED=%d", rng_state)) begin end
        if (rng_state == 0) rng_state = 32'h1;
        repeat (4) @(negedge clk); rst_n = 1;
        $display("UART seed=%0d scenario: reset values and baud divisor", rng_state);
        bus_read32(4'h4, status);
        if ((status & 32'h0c) != 32'h04 || status[0]) $fatal(1, "bad reset status %x", status);
        bus_read32(4'hc, value);
        if (value != 868) $fatal(1, "bad divisor reset %0d", value);

        bus_write32(4'hc, 8);
        $display("UART scenario: TX framing and bit timing");
        bus_write32(4'h0, 8'hA6);
        // Independently sample each serial bit around its center.
        wait (tx == 0);
        repeat (4) @(negedge clk);
        for (bitno = 0; bitno < 8; bitno = bitno + 1) begin
            repeat (8) @(negedge clk);
            if (tx !== ((8'hA6 >> bitno) & 1)) $fatal(1, "TX bit %0d mismatch", bitno);
        end
        repeat (8) @(negedge clk);
        if (tx !== 1) $fatal(1, "TX stop bit mismatch");
        repeat (8) @(negedge clk);
        bus_read32(4'h4, status);
        if (status[0]) $fatal(1, "TX remains busy after frame");

        $display("UART scenario: TX FIFO full and clear");
        bus_write32(4'h8, 2); // disable TX
        for (integer n = 0; n < 16; n = n + 1) bus_write32(0, n);
        bus_read32(4, status);
        if (!status[1]) $fatal(1, "TX FIFO full flag missing");
        bus_write32(0, 8'h77); // full FIFO rejects this write
        bus_write32(8, 7); // enable TX and clear TX FIFO
        bus_read32(4, status);
        if (status[1]) $fatal(1, "TX FIFO clear failed");

        $display("UART scenario: RX byte, FIFO order, and wraparound");
        send_rx(8'h3c, 1);
        bus_read32(4'h4, status);
        if (status[2] || status[5:4] != 0) $fatal(1, "RX status incorrect %x", status);
        bus_read32(4'h0, value);
        if (value[7:0] != 8'h3c) $fatal(1, "RX data mismatch %x", value);
        bus_read32(4'h4, status);
        if (!status[2]) $fatal(1, "RX empty flag not restored");

        for (integer n = 0; n < 16; n = n + 1) send_rx((8'h80 + n), 1);
        bus_read32(4, status);
        if (!status[3] || status[4]) $fatal(1, "RX FIFO full status incorrect %x", status);
        for (integer n = 0; n < 16; n = n + 1) begin
            bus_read32(0, value);
            if (value[7:0] != (8'h80 + n)) $fatal(1, "RX order mismatch at %0d: %02x", n, value[7:0]);
        end
        for (integer n = 0; n < 5; n = n + 1) send_rx((8'h20 + n), 1);
        for (integer n = 0; n < 5; n = n + 1) begin
            bus_read32(0, value);
            if (value[7:0] != (8'h20 + n)) $fatal(1, "RX wrap mismatch at %0d", n);
        end

        $display("UART scenario: seeded randomized RX data, seed=%0d", rng_state);
        for (integer n=0; n<48; n=n+1) begin
            logic [7:0] random_data;
            random_byte(random_data);
            send_rx(random_data, 1);
            bus_read32(0, value);
            if (value[7:0] != random_data)
                $fatal(1, "seed=%0d RX random[%0d] expected=%02x got=%02x", rng_state, n, random_data, value[7:0]);
            rx_cov[random_data[7:6]] = rx_cov[random_data[7:6]] + 1;
        end
        for (integer k=0; k<4; k=k+1)
            if (rx_cov[k] == 0) $fatal(1, "seed=%0d RX coverage bin %0d empty", rng_state, k);
        $display("  UART RX coverage value[7:6] bins=%0d,%0d,%0d,%0d",
            rx_cov[0],rx_cov[1],rx_cov[2],rx_cov[3]);

        $display("UART scenario: framing error, overrun, sticky status, and clear");
        send_rx(8'h55, 0);
        bus_read32(4'h4, status);
        if (!status[5]) $fatal(1, "framing error not set");
        bus_write32(4'h8, 32'hb); // enable and clear RX/errors
        bus_read32(4'h4, status);
        if (status[5:4] != 0) $fatal(1, "error clear failed %x", status);

        // Fill the RX FIFO without reading; the next complete frame must set overrun.
        for (integer n = 0; n < 17; n = n + 1) send_rx(n[7:0], 1);
        bus_read32(4'h4, status);
        if (!status[3] || !status[4]) $fatal(1, "FIFO full/overrun missing %x", status);
        bus_write32(4'h8, 32'hb);
        bus_read32(4'h4, status);
        if (status[3:0] != 4'b0100) $fatal(1, "RX clear failed %x", status);

        $display("UART_TEST_PASS");
        $finish;
    end

    initial begin #2000000; $fatal(1, "UART test timeout"); end
endmodule
