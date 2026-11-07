module gpio_ip (
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
    input  logic [15:0] gpio_in,
    output logic [15:0] gpio_out,
    output logic [15:0] gpio_oe
);
    logic [15:0] input_meta, input_sync;
    logic [15:0] output_latch, direction;

    always_comb begin
        bus_ready = bus_valid;
        bus_error = bus_valid && (bus_addr[1:0] != 0 || bus_addr > 4'h8);
        bus_rdata = 32'b0;
        if (bus_valid && !bus_write && !bus_error) begin
            case (bus_addr)
                4'h0: bus_rdata = {16'b0, input_sync};
                4'h4: bus_rdata = {16'b0, output_latch};
                4'h8: bus_rdata = {16'b0, direction};
                default: bus_rdata = 0;
            endcase
        end
    end

    assign gpio_out = output_latch;
    assign gpio_oe = direction;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            input_meta <= 0;
            input_sync <= 0;
            output_latch <= 0;
            direction <= 0;
        end else begin
            input_meta <= gpio_in;
            input_sync <= input_meta;
            if (bus_valid && bus_ready && bus_write && !bus_error) begin
                case (bus_addr)
                    4'h4: begin
                        if (bus_wstrb[0]) output_latch[7:0] <= bus_wdata[7:0];
                        if (bus_wstrb[1]) output_latch[15:8] <= bus_wdata[15:8];
                    end
                    4'h8: begin
                        if (bus_wstrb[0]) direction[7:0] <= bus_wdata[7:0];
                        if (bus_wstrb[1]) direction[15:8] <= bus_wdata[15:8];
                    end
                    default: ;
                endcase
            end
        end
    end
endmodule
