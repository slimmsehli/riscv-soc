module soc_top #(
    parameter SRAM_INIT_FILE = "",
    parameter integer SRAM_WORDS = 16384
) (
    input logic clk,
    input logic rst_n,
    input logic uart_rx,
    output logic uart_tx,
    input logic [15:0] gpio_in,
    output logic [15:0] gpio_out,
    output logic [15:0] gpio_oe,
    inout wire i2c_scl,
    inout wire i2c_sda,
    output logic cpu_trap
);
    logic core_rst_n;
    soc_reset_sync reset_sync(.clk, .arst_n(rst_n), .rst_n(core_rst_n));

    logic cpu_valid, cpu_ready, cpu_write, cpu_error;
    logic [31:0] cpu_addr, cpu_wdata, cpu_rdata;
    logic [3:0] cpu_wstrb;
    logic dma_mem_valid, dma_mem_ready, dma_mem_write, dma_mem_error;
    logic [31:0] dma_mem_addr, dma_mem_wdata, dma_mem_rdata;
    logic [3:0] dma_mem_wstrb;

    logic uart_valid, uart_ready, uart_error, uart_write;
    logic [3:0] uart_addr, uart_wstrb;
    logic [31:0] uart_wdata, uart_rdata;
    logic dma_cfg_valid, dma_cfg_ready, dma_cfg_error, dma_cfg_write;
    logic [3:0] dma_cfg_addr, dma_cfg_wstrb;
    logic [31:0] dma_cfg_wdata, dma_cfg_rdata;
    logic i2c_valid, i2c_ready, i2c_error, i2c_write;
    logic [3:0] i2c_addr, i2c_wstrb;
    logic [31:0] i2c_wdata, i2c_rdata;
    logic gpio_valid, gpio_ready, gpio_error, gpio_write;
    logic [3:0] gpio_addr, gpio_wstrb;
    logic [31:0] gpio_wdata, gpio_rdata;
    logic mem_valid, mem_ready, mem_write, mem_error;
    logic [31:0] mem_addr, mem_wdata, mem_rdata;
    logic [3:0] mem_wstrb;
    logic i2c_scl_low, i2c_sda_low;
    assign i2c_scl = i2c_scl_low ? 1'b0 : 1'bz;
    assign i2c_sda = i2c_sda_low ? 1'b0 : 1'bz;

    picorv32_bus_wrapper cpu(.clk, .rst_n(core_rst_n), .bus_valid(cpu_valid), .bus_ready(cpu_ready),
        .bus_addr(cpu_addr), .bus_wdata(cpu_wdata), .bus_write(cpu_write), .bus_wstrb(cpu_wstrb),
        .bus_rdata(cpu_rdata), .bus_error(cpu_error), .trap(cpu_trap));
    dma_ip dma(.clk, .rst_n(core_rst_n), .cfg_valid(dma_cfg_valid), .cfg_ready(dma_cfg_ready),
        .cfg_addr(dma_cfg_addr), .cfg_write(dma_cfg_write), .cfg_wdata(dma_cfg_wdata),
        .cfg_wstrb(dma_cfg_wstrb), .cfg_rdata(dma_cfg_rdata), .cfg_error(dma_cfg_error),
        .mem_valid(dma_mem_valid), .mem_ready(dma_mem_ready), .mem_addr(dma_mem_addr),
        .mem_write(dma_mem_write), .mem_wdata(dma_mem_wdata), .mem_wstrb(dma_mem_wstrb),
        .mem_rdata(dma_mem_rdata), .mem_error(dma_mem_error));
    uart_ip uart(.clk, .rst_n(core_rst_n), .bus_valid(uart_valid), .bus_ready(uart_ready),
        .bus_addr(uart_addr), .bus_write(uart_write), .bus_wdata(uart_wdata), .bus_wstrb(uart_wstrb),
        .bus_rdata(uart_rdata), .bus_error(uart_error), .uart_rx, .uart_tx);
    i2c_master i2c(.clk, .rst_n(core_rst_n), .cfg_valid(i2c_valid), .cfg_ready(i2c_ready),
        .cfg_addr(i2c_addr), .cfg_write(i2c_write), .cfg_wdata(i2c_wdata), .cfg_wstrb(i2c_wstrb),
        .cfg_rdata(i2c_rdata), .cfg_error(i2c_error), .i2c_scl_in(i2c_scl),
        .i2c_scl_low, .i2c_sda_in(i2c_sda), .i2c_sda_low);
    gpio_ip gpio(.clk, .rst_n(core_rst_n), .bus_valid(gpio_valid), .bus_ready(gpio_ready),
        .bus_addr(gpio_addr), .bus_write(gpio_write), .bus_wdata(gpio_wdata),
        .bus_wstrb(gpio_wstrb), .bus_rdata(gpio_rdata), .bus_error(gpio_error),
        .gpio_in, .gpio_out, .gpio_oe);
    soc_sram #(.WORDS(SRAM_WORDS), .INIT_FILE(SRAM_INIT_FILE)) sram(.clk,
        .valid(mem_valid), .ready(mem_ready), .addr(mem_addr), .write(mem_write), .wdata(mem_wdata),
        .wstrb(mem_wstrb), .rdata(mem_rdata), .error(mem_error));

    soc_bus_fabric fabric(.clk, .rst_n(core_rst_n),
        .cpu_valid, .cpu_ready, .cpu_addr, .cpu_wdata, .cpu_write, .cpu_wstrb, .cpu_rdata, .cpu_error,
        .dma_valid(dma_mem_valid), .dma_ready(dma_mem_ready), .dma_addr(dma_mem_addr),
        .dma_wdata(dma_mem_wdata), .dma_write(dma_mem_write), .dma_wstrb(dma_mem_wstrb),
        .dma_rdata(dma_mem_rdata), .dma_error(dma_mem_error),
        .uart_valid, .uart_ready, .uart_addr, .uart_write, .uart_wdata, .uart_wstrb, .uart_rdata, .uart_error,
        .dma_cfg_valid, .dma_cfg_ready, .dma_cfg_addr, .dma_cfg_write, .dma_cfg_wdata,
        .dma_cfg_wstrb, .dma_cfg_rdata, .dma_cfg_error,
        .i2c_valid, .i2c_ready, .i2c_addr, .i2c_write, .i2c_wdata, .i2c_wstrb, .i2c_rdata, .i2c_error,
        .gpio_valid, .gpio_ready, .gpio_addr, .gpio_write, .gpio_wdata, .gpio_wstrb, .gpio_rdata, .gpio_error,
        .mem_valid, .mem_ready, .mem_addr, .mem_wdata, .mem_write, .mem_wstrb, .mem_rdata, .mem_error);
endmodule
