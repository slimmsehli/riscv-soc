module dma_ip (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        cfg_valid,
    output logic        cfg_ready,
    input  logic [3:0]  cfg_addr,
    input  logic        cfg_write,
    input  logic [31:0] cfg_wdata,
    input  logic [3:0]  cfg_wstrb,
    output logic [31:0] cfg_rdata,
    output logic        cfg_error,
    output logic        mem_valid,
    input  logic        mem_ready,
    output logic [31:0] mem_addr,
    output logic        mem_write,
    output logic [31:0] mem_wdata,
    output logic [3:0]  mem_wstrb,
    input  logic [31:0] mem_rdata,
    input  logic        mem_error
);
    typedef enum logic [1:0] {IDLE, READ_BYTE, WRITE_BYTE} state_t;
    state_t state;
    logic [31:0] src, dst, length;
    logic [31:0] current_src, current_dst, remaining;
    logic [7:0] byte_latch;
    logic busy, done, error;

    always_comb begin
        cfg_ready = cfg_valid;
        cfg_error = 1'b0;
        cfg_rdata = 0;
        if (cfg_valid && (cfg_addr[1:0] != 0 || cfg_addr > 4'hc)) cfg_error = 1'b1;
        if (cfg_valid && !cfg_write) begin
            case (cfg_addr)
                4'h0: cfg_rdata = src;
                4'h4: cfg_rdata = dst;
                4'h8: cfg_rdata = length;
                4'hc: cfg_rdata = {29'b0, error, done, busy};
                default: cfg_rdata = 0;
            endcase
        end
    end

    always_comb begin
        mem_valid = (state == READ_BYTE) || (state == WRITE_BYTE);
        mem_write = (state == WRITE_BYTE);
        mem_addr = state == WRITE_BYTE ? {current_dst[31:2], 2'b00} : {current_src[31:2], 2'b00};
        mem_wdata = {24'b0, byte_latch} << (8 * current_dst[1:0]);
        mem_wstrb = state == WRITE_BYTE ? (4'b0001 << current_dst[1:0]) : 4'b0000;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            src <= 0; dst <= 0; length <= 0;
            current_src <= 0; current_dst <= 0; remaining <= 0; byte_latch <= 0;
            busy <= 0; done <= 0; error <= 0;
        end else begin
            if (cfg_valid && cfg_ready && cfg_write && !cfg_error) begin
                case (cfg_addr)
                    4'h0: if (!busy && |cfg_wstrb) src <= cfg_wdata;
                    4'h4: if (!busy && |cfg_wstrb) dst <= cfg_wdata;
                    4'h8: if (!busy && |cfg_wstrb) length <= cfg_wdata;
                    4'hc: begin
                        if (cfg_wdata[1]) done <= 0;
                        if (cfg_wdata[2]) error <= 0;
                        if (cfg_wdata[0]) begin
                            if (busy) error <= 1;
                            else if (length == 0) begin busy <= 0; done <= 1; end
                            else begin
                                busy <= 1; done <= 0;
                                current_src <= src; current_dst <= dst; remaining <= length;
                                state <= READ_BYTE;
                            end
                        end
                    end
                    default: ;
                endcase
            end

            if (mem_valid && mem_ready) begin
                if (mem_error) begin state <= IDLE; busy <= 0; error <= 1; end
                else if (state == READ_BYTE) begin
                    byte_latch <= mem_rdata[8*current_src[1:0] +: 8];
                    state <= WRITE_BYTE;
                end else if (remaining == 1) begin
                    state <= IDLE; busy <= 0; done <= 1; remaining <= 0;
                end else begin
                    current_src <= current_src + 1'b1;
                    current_dst <= current_dst + 1'b1;
                    remaining <= remaining - 1'b1;
                    state <= READ_BYTE;
                end
            end
        end
    end
endmodule
