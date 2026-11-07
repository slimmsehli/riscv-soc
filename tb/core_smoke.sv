`timescale 1ns/1ps
module core_smoke;
    logic clk = 0;
    logic resetn = 0;
    always #5 clk = ~clk;

    wire trap, mem_valid, mem_instr;
    wire [31:0] mem_addr, mem_wdata;
    wire [3:0] mem_wstrb;
    wire mem_ready = transaction_pending;
    logic [31:0] mem_rdata;
    logic [31:0] memory [0:16383];
    logic transaction_pending = 0;
    logic [31:0] saved_addr, saved_wdata;
    logic [3:0] saved_wstrb;
    integer cycles = 0;
    integer loads = 0;
    integer stores = 0;
    logic [31:0] completion = 0;

    always_comb begin
        if (transaction_pending && saved_addr < 65536 && saved_wstrb == 0)
            mem_rdata = memory[saved_addr[15:2]];
        else
            mem_rdata = 0;
    end

    picorv32 #(
        .ENABLE_COUNTERS(0), .ENABLE_COUNTERS64(0), .ENABLE_REGS_16_31(1),
        .COMPRESSED_ISA(0), .ENABLE_MUL(0), .ENABLE_DIV(0),
        .ENABLE_IRQ(0), .PROGADDR_RESET(0), .STACKADDR(32'h0000_fffc)
    ) cpu (
        .clk(clk), .resetn(resetn), .trap(trap),
        .mem_valid(mem_valid), .mem_instr(mem_instr), .mem_ready(mem_ready),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata),
        .mem_la_read(), .mem_la_write(), .mem_la_addr(), .mem_la_wdata(), .mem_la_wstrb(),
        .pcpi_valid(), .pcpi_insn(), .pcpi_rs1(), .pcpi_rs2(),
        .pcpi_wr(1'b0), .pcpi_rd(32'b0), .pcpi_wait(1'b0), .pcpi_ready(1'b0),
        .irq(32'b0), .eoi(), .trace_valid(), .trace_data()
    );

    initial begin
        $readmemh("build/core_smoke.hex", memory);
        repeat (5) @(posedge clk);
        resetn <= 1;
    end

    always @(posedge clk) begin
        cycles <= cycles + 1;
        if (!resetn) begin
            transaction_pending <= 0;
        end else if (mem_valid && !transaction_pending) begin
            transaction_pending <= 1;
            saved_addr <= mem_addr;
            saved_wdata <= mem_wdata;
            saved_wstrb <= mem_wstrb;
        end else if (transaction_pending) begin
            transaction_pending <= 0;
            if (saved_addr == 32'h10000000 && saved_wstrb != 0) begin
                completion <= saved_wdata;
                stores <= stores + 1;
            end else if (saved_addr < 65536) begin
                if (saved_wstrb == 0) begin
                    loads <= loads + 1;
                end else begin
                    for (integer lane = 0; lane < 4; lane = lane + 1)
                        if (saved_wstrb[lane])
                            memory[saved_addr[15:2]][8*lane +: 8] <= saved_wdata[8*lane +: 8];
                    stores <= stores + 1;
                end
            end else begin
                $fatal(1, "unexpected access at %08x", saved_addr);
            end
        end

        if (completion != 0) begin
            if (completion != 32'h600d600d)
                $fatal(1, "software reported failure: %08x", completion);
            if (loads < 8 || stores < 8)
                $fatal(1, "insufficient memory traffic loads=%0d stores=%0d", loads, stores);
            $display("CORE_SMOKE_PASS cycles=%0d loads=%0d stores=%0d", cycles, loads, stores);
            $finish;
        end
        if (trap)
            $fatal(1, "core trapped before completion");
        if (cycles > 200000)
            $fatal(1, "timeout waiting for software completion");
    end
endmodule
