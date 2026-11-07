module soc_bus_fabric (
    input logic clk, rst_n,
    input logic cpu_valid,
    output logic cpu_ready,
    input logic [31:0] cpu_addr, cpu_wdata,
    input logic cpu_write,
    input logic [3:0] cpu_wstrb,
    output logic [31:0] cpu_rdata,
    output logic cpu_error,
    input logic dma_valid,
    output logic dma_ready,
    input logic [31:0] dma_addr, dma_wdata,
    input logic dma_write,
    input logic [3:0] dma_wstrb,
    output logic [31:0] dma_rdata,
    output logic dma_error,
    output logic uart_valid,
    input logic uart_ready,
    output logic [3:0] uart_addr,
    output logic uart_write,
    output logic [31:0] uart_wdata,
    output logic [3:0] uart_wstrb,
    input logic [31:0] uart_rdata,
    input logic uart_error,
    output logic dma_cfg_valid,
    input logic dma_cfg_ready,
    output logic [3:0] dma_cfg_addr,
    output logic dma_cfg_write,
    output logic [31:0] dma_cfg_wdata,
    output logic [3:0] dma_cfg_wstrb,
    input logic [31:0] dma_cfg_rdata,
    input logic dma_cfg_error,
    output logic i2c_valid,
    input logic i2c_ready,
    output logic [3:0] i2c_addr,
    output logic i2c_write,
    output logic [31:0] i2c_wdata,
    output logic [3:0] i2c_wstrb,
    input logic [31:0] i2c_rdata,
    input logic i2c_error,
    output logic gpio_valid,
    input logic gpio_ready,
    output logic [3:0] gpio_addr,
    output logic gpio_write,
    output logic [31:0] gpio_wdata,
    output logic [3:0] gpio_wstrb,
    input logic [31:0] gpio_rdata,
    input logic gpio_error,
    output logic spi_valid,
    input logic spi_ready,
    output logic [3:0] spi_addr,
    output logic spi_write,
    output logic [31:0] spi_wdata,
    output logic [3:0] spi_wstrb,
    input logic [31:0] spi_rdata,
    input logic spi_error,
    output logic mem_valid,
    input logic mem_ready,
    output logic [31:0] mem_addr, mem_wdata,
    output logic mem_write,
    output logic [3:0] mem_wstrb,
    input logic [31:0] mem_rdata,
    input logic mem_error
);
    logic owner_dma;
    logic [4:0] cpu_streak;
    logic choose_dma;
    logic selected_valid, selected_write;
    logic selected_dma;
    logic [31:0] selected_addr, selected_wdata;
    logic [3:0] selected_wstrb;
    logic target_ready, target_error;
    logic [31:0] target_rdata;

    always_comb begin
        choose_dma = dma_valid && (!cpu_valid || (cpu_streak >= 16));
        selected_dma = owner_dma || choose_dma;
        selected_valid = owner_dma ? dma_valid : cpu_valid;
        selected_addr = owner_dma ? dma_addr : cpu_addr;
        selected_wdata = owner_dma ? dma_wdata : cpu_wdata;
        selected_write = owner_dma ? dma_write : cpu_write;
        selected_wstrb = owner_dma ? dma_wstrb : cpu_wstrb;
        if (!owner_dma) begin
            selected_valid = choose_dma ? dma_valid : cpu_valid;
            selected_addr = choose_dma ? dma_addr : cpu_addr;
            selected_wdata = choose_dma ? dma_wdata : cpu_wdata;
            selected_write = choose_dma ? dma_write : cpu_write;
            selected_wstrb = choose_dma ? dma_wstrb : cpu_wstrb;
        end
        uart_valid = 0; dma_cfg_valid = 0; i2c_valid = 0; gpio_valid = 0; spi_valid = 0;
        uart_addr = selected_addr[3:0]; dma_cfg_addr = selected_addr[3:0]; i2c_addr = selected_addr[3:0]; gpio_addr = selected_addr[3:0]; spi_addr = selected_addr[3:0];
        uart_write = selected_write; dma_cfg_write = selected_write; i2c_write = selected_write; gpio_write = selected_write; spi_write = selected_write;
        uart_wdata = selected_wdata; dma_cfg_wdata = selected_wdata; i2c_wdata = selected_wdata; gpio_wdata = selected_wdata; spi_wdata = selected_wdata;
        uart_wstrb = selected_wstrb; dma_cfg_wstrb = selected_wstrb; i2c_wstrb = selected_wstrb; gpio_wstrb = selected_wstrb; spi_wstrb = selected_wstrb;
        mem_valid = 0; mem_addr = selected_addr; mem_write = selected_write;
        mem_wdata = selected_wdata; mem_wstrb = selected_wstrb;
        target_ready = 0; target_error = 0; target_rdata = 0;
        if (selected_valid) begin
            if (selected_addr < 32'h00010000) begin
                mem_valid = 1; target_ready = mem_ready; target_error = mem_error; target_rdata = mem_rdata;
            end else if (selected_addr[31:12] == 20'h10000 && !selected_dma) begin
                uart_valid = 1; target_ready = uart_ready; target_error = uart_error; target_rdata = uart_rdata;
            end else if (selected_addr[31:12] == 20'h10001 && !selected_dma) begin
                dma_cfg_valid = 1; target_ready = dma_cfg_ready; target_error = dma_cfg_error; target_rdata = dma_cfg_rdata;
            end else if (selected_addr[31:12] == 20'h10002 && !selected_dma) begin
                i2c_valid = 1; target_ready = i2c_ready; target_error = i2c_error; target_rdata = i2c_rdata;
            end else if (selected_addr[31:12] == 20'h10003 && !selected_dma) begin
                target_ready = 1; target_error = 0; target_rdata = 0;
            end else if (selected_addr[31:12] == 20'h10004 && !selected_dma) begin
                gpio_valid = 1; target_ready = gpio_ready; target_error = gpio_error; target_rdata = gpio_rdata;
            end else if (selected_addr[31:12] == 20'h10005 && !selected_dma) begin
                spi_valid = 1; target_ready = spi_ready; target_error = spi_error; target_rdata = spi_rdata;
            end else begin target_ready = 1; target_error = 1; end
        end
        cpu_ready = selected_valid && target_ready && !owner_dma && !choose_dma;
        dma_ready = selected_valid && target_ready && (owner_dma || choose_dma);
        cpu_rdata = target_rdata; dma_rdata = target_rdata;
        cpu_error = target_error; dma_error = target_error;
        // Ownership response is routed only to the selected master.
        if (owner_dma || choose_dma) begin cpu_ready = 0; cpu_error = 0; cpu_rdata = 0; end
        else begin dma_ready = 0; dma_error = 0; dma_rdata = 0; end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin owner_dma <= 0; cpu_streak <= 0; end
        else if (owner_dma && target_ready) begin
            owner_dma <= 0;
        end else if (!owner_dma && choose_dma && dma_valid && !target_ready) begin
            owner_dma <= 1;
        end else if (!owner_dma && !choose_dma && cpu_valid && target_ready) begin
            if (dma_valid && cpu_streak < 16) cpu_streak <= cpu_streak + 1'b1;
            else if (!dma_valid) cpu_streak <= 0;
        end else if (!owner_dma && choose_dma && dma_valid && target_ready) begin
            cpu_streak <= 0;
        end
    end
endmodule
