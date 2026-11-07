`timescale 1ns/1ps
module soc_fabric_tb;
    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    logic cv = 0, cw = 0, dv = 0, dw = 0;
    logic [31:0] ca = 0, cd = 0, da = 0, dd = 0;
    logic [3:0] cs = 0, ds = 0;
    wire cr, ce, dr, de;
    wire [31:0] crd, drd;
    wire uv, uwrite, dcv, dcwrite, iv, iwrite, mv, mwrite;
    wire [3:0] ua, us, dca, dcs, ia, is, ms;
    wire [31:0] ud, dcd, id, md, ma;
    wire [31:0] ur, dcr, ir, mr;
    wire ue, dce, ie, me, urdy, dcrdy, irdy, mrdy;
    logic [31:0] memory [0:255];
    logic stall_mem = 0;
    integer cpu_count = 0, dma_count = 0;

    assign urdy = uv; assign ue = 0; assign ur = 32'h11112222;
    assign dcrdy = dcv; assign dce = 0; assign dcr = 32'h33334444;
    assign irdy = iv; assign ie = 0; assign ir = 32'h55556666;
    assign mrdy = mv && !stall_mem; assign me = 0;
    assign mr = memory[ma[9:2]];

    soc_bus_fabric dut(.clk, .rst_n,
        .cpu_valid(cv), .cpu_ready(cr), .cpu_addr(ca), .cpu_wdata(cd), .cpu_write(cw),
        .cpu_wstrb(cs), .cpu_rdata(crd), .cpu_error(ce),
        .dma_valid(dv), .dma_ready(dr), .dma_addr(da), .dma_wdata(dd), .dma_write(dw),
        .dma_wstrb(ds), .dma_rdata(drd), .dma_error(de),
        .uart_valid(uv), .uart_ready(urdy), .uart_addr(ua), .uart_write(uwrite), .uart_wdata(ud),
        .uart_wstrb(us), .uart_rdata(ur), .uart_error(ue),
        .dma_cfg_valid(dcv), .dma_cfg_ready(dcrdy), .dma_cfg_addr(dca), .dma_cfg_write(dcwrite),
        .dma_cfg_wdata(dcd), .dma_cfg_wstrb(dcs), .dma_cfg_rdata(dcr), .dma_cfg_error(dce),
        .i2c_valid(iv), .i2c_ready(irdy), .i2c_addr(ia), .i2c_write(iwrite), .i2c_wdata(id),
        .i2c_wstrb(is), .i2c_rdata(ir), .i2c_error(ie),
        .mem_valid(mv), .mem_ready(mrdy), .mem_addr(ma), .mem_wdata(md), .mem_write(mwrite),
        .mem_wstrb(ms), .mem_rdata(mr), .mem_error(me));

    always_ff @(posedge clk) begin
        if (mv && mrdy && mwrite)
            for (integer l = 0; l < 4; l = l + 1)
                if (ms[l]) memory[ma[9:2]][8*l +: 8] <= md[8*l +: 8];
        if (cv && cr) cpu_count <= cpu_count + 1;
        if (dv && dr) dma_count <= dma_count + 1;
    end

    task automatic cpu_xfer(input logic [31:0] a, input logic wr, input logic [31:0] data,
                             input logic [3:0] strobes, input logic expect_err,
                             input logic [31:0] expected);
        @(negedge clk); cv=1; ca=a; cw=wr; cd=data; cs=strobes; #1;
        if (!cr) $fatal(1, "CPU request not ready at %08x", a);
        if (ce != expect_err) $fatal(1, "CPU error mismatch at %08x", a);
        if (!wr && !expect_err && crd != expected) $fatal(1, "CPU read %08x got %08x expected %08x", a, crd, expected);
        @(posedge clk); #1; @(negedge clk); cv=0; cw=0; cs=0;
    endtask

    initial begin
        for (integer i=0;i<256;i=i+1) memory[i]=0;
        repeat (3) @(negedge clk); rst_n=1;
        cpu_xfer(32'h20, 1, 32'hdeadbeef, 4'hf, 0, 0);
        cpu_xfer(32'h20, 0, 0, 0, 0, 32'hdeadbeef);
        cpu_xfer(32'h10000004, 0, 0, 0, 0, 32'h11112222);
        cpu_xfer(32'h10001008, 0, 0, 0, 0, 32'h33334444);
        cpu_xfer(32'h1000200c, 0, 0, 0, 0, 32'h55556666);
        cpu_xfer(32'h20000000, 0, 0, 0, 1, 0);
        // DMA may access SRAM, but its peripheral-window request must complete with error.
        @(negedge clk); dv=1; da=32'h10000000; #1;
        if (!dr || !de) $fatal(1, "DMA peripheral access did not error");
        @(posedge clk); #1; @(negedge clk); dv=0;

        // A stalled CPU request keeps its address and ownership until response.
        cv=1; ca=32'h28; dv=1; da=32'h2c; stall_mem=1;
        repeat (2) begin
            @(posedge clk); #1;
            if (ma != 32'h28 || cr || dr) $fatal(1, "stalled transaction ownership changed");
        end
        @(negedge clk); stall_mem=0; #1;
        if (!cr) $fatal(1, "CPU stalled request did not complete");
        @(posedge clk); #1; @(negedge clk); cv=0; #1;
        if (!dr) $fatal(1, "DMA did not receive bus after stalled CPU completion");
        @(posedge clk); #1; @(negedge clk); dv=0;

        // Hold both masters valid. CPU receives priority, but DMA must win by the bound.
        cv=1; ca=32'h20; dv=1; da=32'h24;
        repeat (20) @(posedge clk);
        #1;
        if (dma_count == 0 || cpu_count < 16) $fatal(1, "arbitration fairness failed cpu=%0d dma=%0d", cpu_count, dma_count);
        cv=0; dv=0;
        $display("SOC_FABRIC_PASS cpu_grants=%0d dma_grants=%0d", cpu_count, dma_count);
        $finish;
    end
    initial begin #10000; $fatal(1, "fabric test timeout"); end
endmodule
