module spi_master (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        bus_valid,
    output logic        bus_ready,
    input  logic [3:0]  bus_addr,
    input  logic        bus_write,
    input  logic [31:0] bus_wdata,
    input  logic [3:0]  bus_wstrb,
    output logic [31:0] bus_rdata,
    output logic        bus_error,
    input  logic        spi_miso,
    output logic        spi_mosi,
    output logic        spi_sck,
    output logic [3:0]  spi_cs_n
);
    logic [7:0] tx_data, rx_data, tx_shift, rx_shift;
    logic [31:0] divider, timer;
    logic [3:0] chip_select;
    logic cpol, cpha, busy, done, error;
    logic [2:0] bit_index;
    logic phase;

    always_comb begin
        bus_ready = bus_valid;
        bus_error = bus_valid && (bus_addr[1:0] != 0 || bus_addr > 4'hc);
        bus_rdata = 0;
        if (bus_valid && !bus_write && !bus_error) begin
            case (bus_addr)
                4'h0: bus_rdata = {24'b0, rx_data};
                4'h4: bus_rdata = {28'b0, error, (done && !busy), done, busy};
                4'h8: bus_rdata = divider;
                4'hc: bus_rdata = {26'b0, cpha, cpol, chip_select};
                default: bus_rdata = 0;
            endcase
        end
    end

    always_comb begin
        spi_sck = cpol;
        spi_cs_n = 4'hf;
        if (busy) begin
            spi_sck = phase ? !cpol : cpol;
            spi_cs_n = ~chip_select;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_data <= 0; rx_data <= 0; tx_shift <= 0; rx_shift <= 0;
            divider <= 2; chip_select <= 4'b0001; cpol <= 0; cpha <= 0;
            busy <= 0; done <= 0; error <= 0; bit_index <= 0; phase <= 0; timer <= 0;
            spi_mosi <= 0;
        end else begin
            if (bus_valid && bus_ready && bus_write && !bus_error) begin
                case (bus_addr)
                    4'h0: if (|bus_wstrb) tx_data <= bus_wdata[7:0];
                    4'h8: if (|bus_wstrb) divider <= bus_wdata < 2 ? 2 : bus_wdata;
                    4'hc: if (bus_wstrb[0]) begin
                        if (bus_wdata[3:0] != 0 && $onehot(bus_wdata[3:0])) begin
                            chip_select <= bus_wdata[3:0];
                            cpol <= bus_wdata[4]; cpha <= bus_wdata[5];
                        end else error <= 1;
                    end
                    4'h4: begin
                        if (bus_wdata[1]) done <= 0;
                        if (bus_wdata[3]) error <= 0;
                        if (bus_wdata[0]) begin
                            if (busy) error <= 1;
                            else begin
                                busy <= 1; done <= 0; bit_index <= 0; phase <= 0;
                                tx_shift <= tx_data; rx_shift <= 0; timer <= divider - 1'b1;
                                spi_mosi <= cpha ? 1'b0 : tx_data[7];
                            end
                        end
                    end
                    default: ;
                endcase
            end

            if (busy) begin
                if (timer != 0) timer <= timer - 1'b1;
                else begin
                    timer <= divider - 1'b1;
                    if (!phase) begin
                        // Leading edge: CPHA=1 launches data; CPHA=0 samples it.
                        phase <= 1;
                        if (cpha) begin
                            spi_mosi <= tx_shift[7];
                        end else begin
                            rx_shift <= {rx_shift[6:0], spi_miso};
                            if (bit_index == 7) rx_data <= {rx_shift[6:0], spi_miso};
                        end
                    end else begin
                        // Trailing edge: CPHA=0 launches the next bit; CPHA=1 samples.
                        phase <= 0;
                        if (cpha) begin
                            rx_shift <= {rx_shift[6:0], spi_miso};
                            if (bit_index == 7) rx_data <= {rx_shift[6:0], spi_miso};
                        end
                        if (bit_index == 7) begin
                            // Keep the final bit stable through the trailing
                            // edge; the next transfer will load its first bit.
                            busy <= 0; done <= 1;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                            tx_shift <= {tx_shift[6:0], 1'b0};
                            if (!cpha) spi_mosi <= tx_shift[6];
                        end
                    end
                end
            end
        end
    end
endmodule
