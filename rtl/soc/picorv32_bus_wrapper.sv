module picorv32_bus_wrapper (
    input logic clk, rst_n,
    output logic bus_valid,
    input logic bus_ready,
    output logic [31:0] bus_addr, bus_wdata,
    output logic bus_write,
    output logic [3:0] bus_wstrb,
    input logic [31:0] bus_rdata,
    input logic bus_error,
    output logic trap
);
    logic core_valid, core_ready, core_instr;
    logic [31:0] core_addr, core_wdata, core_rdata;
    logic [3:0] core_wstrb;
    assign bus_valid = core_valid;
    assign bus_addr = core_addr;
    assign bus_wdata = core_wdata;
    assign bus_write = |core_wstrb;
    assign bus_wstrb = core_wstrb;
    assign core_ready = bus_ready;
    assign core_rdata = bus_rdata;

    picorv32 #(
        .ENABLE_COUNTERS(0), .ENABLE_COUNTERS64(0), .ENABLE_REGS_16_31(1),
        .COMPRESSED_ISA(0), .ENABLE_MUL(0), .ENABLE_DIV(0), .ENABLE_IRQ(0),
        .PROGADDR_RESET(32'h00000000), .STACKADDR(32'h0000fffc)
    ) core (
        .clk(clk), .resetn(rst_n), .trap(trap),
        .mem_valid(core_valid), .mem_instr(core_instr), .mem_ready(core_ready),
        .mem_addr(core_addr), .mem_wdata(core_wdata), .mem_wstrb(core_wstrb), .mem_rdata(core_rdata),
        .mem_la_read(), .mem_la_write(), .mem_la_addr(), .mem_la_wdata(), .mem_la_wstrb(),
        .pcpi_valid(), .pcpi_insn(), .pcpi_rs1(), .pcpi_rs2(), .pcpi_wr(1'b0), .pcpi_rd(32'b0),
        .pcpi_wait(1'b0), .pcpi_ready(1'b0), .irq(32'b0), .eoi(), .trace_valid(), .trace_data()
    );
endmodule
