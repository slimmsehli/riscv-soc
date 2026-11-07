module uart_ip (
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
    input  logic        uart_rx,
    output logic        uart_tx
);
    logic [7:0] tx_fifo [0:15];
    logic [7:0] rx_fifo [0:15];
    logic [3:0] tx_rptr, tx_wptr, rx_rptr, rx_wptr;
    logic [4:0] tx_count, rx_count;
    logic [31:0] divisor;
    logic tx_enable, rx_enable;
    logic overrun, framing_error;

    logic tx_busy;
    logic [9:0] tx_frame;
    logic [3:0] tx_bit;
    logic [31:0] tx_timer;

    typedef enum logic [1:0] {RX_IDLE, RX_START, RX_DATA, RX_STOP} rx_state_t;
    rx_state_t rx_state;
    logic [31:0] rx_timer;
    logic [2:0] rx_bit;
    logic [7:0] rx_shift;
    logic rx_sync1, rx_sync2;

    wire tx_full = tx_count == 16;
    wire tx_empty = tx_count == 0;
    wire rx_full = rx_count == 16;
    wire rx_empty = rx_count == 0;
    wire tx_push = bus_valid && bus_ready && bus_write && bus_addr == 4'h0 && !tx_full;
    wire tx_pop = !tx_busy && tx_enable && !tx_empty;
    wire rx_pop = bus_valid && bus_ready && !bus_write && bus_addr == 4'h0 && !rx_empty;
    wire rx_push = rx_state == RX_STOP && rx_timer == 0 && rx_sync2 && !rx_full;

    always_comb begin
        bus_ready = bus_valid;
        bus_error = 1'b0;
        bus_rdata = 32'b0;
        if (bus_valid && bus_addr[3:2] == 2'b00 && bus_addr[1:0] != 0)
            bus_error = 1'b1;
        if (bus_valid && !bus_write) begin
            case (bus_addr)
                4'h0: bus_rdata = rx_empty ? 32'b0 : {24'b0, rx_fifo[rx_rptr]};
                4'h4: bus_rdata = {26'b0, framing_error, overrun, rx_full, rx_empty, tx_full, tx_busy};
                4'h8: bus_rdata = {30'b0, rx_enable, tx_enable};
                4'hc: bus_rdata = divisor;
                default: bus_rdata = 32'b0;
            endcase
        end
    end

    assign uart_tx = tx_busy ? tx_frame[0] : 1'b1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_rptr <= 0; tx_wptr <= 0; tx_count <= 0;
            rx_rptr <= 0; rx_wptr <= 0; rx_count <= 0;
            divisor <= 868; tx_enable <= 1; rx_enable <= 1;
            overrun <= 0; framing_error <= 0;
            tx_busy <= 0; tx_frame <= 10'h3ff; tx_bit <= 0; tx_timer <= 0;
            rx_state <= RX_IDLE; rx_timer <= 0; rx_bit <= 0; rx_shift <= 0;
            rx_sync1 <= 1; rx_sync2 <= 1;
        end else begin
            rx_sync1 <= uart_rx;
            rx_sync2 <= rx_sync1;

            if (bus_valid && bus_ready && bus_write) begin
                case (bus_addr)
                    4'h8: if (bus_wstrb[0]) begin
                        tx_enable <= bus_wdata[0];
                        rx_enable <= bus_wdata[1];
                        if (bus_wdata[2]) begin tx_rptr <= 0; tx_wptr <= 0; tx_count <= 0; end
                        if (bus_wdata[3]) begin
                            rx_rptr <= 0; rx_wptr <= 0; rx_count <= 0;
                            overrun <= 0; framing_error <= 0;
                        end
                    end
                    4'hc: if (|bus_wstrb) divisor <= bus_wdata < 2 ? 2 : bus_wdata;
                    default: ;
                endcase
            end

            if (tx_push) begin tx_fifo[tx_wptr] <= bus_wdata[7:0]; tx_wptr <= tx_wptr + 1'b1; end
            if (tx_pop) begin tx_rptr <= tx_rptr + 1'b1; end
            case ({tx_push, tx_pop})
                2'b10: tx_count <= tx_count + 1'b1;
                2'b01: tx_count <= tx_count - 1'b1;
                default: ;
            endcase

            if (!tx_busy && tx_enable && !tx_empty) begin
                tx_frame <= {1'b1, tx_fifo[tx_rptr], 1'b0};
                tx_busy <= 1;
                tx_bit <= 0;
                tx_timer <= divisor - 1'b1;
            end else if (tx_busy) begin
                if (tx_timer != 0) tx_timer <= tx_timer - 1'b1;
                else begin
                    if (tx_bit == 9) begin tx_busy <= 0; tx_frame <= 10'h3ff; end
                    else begin tx_frame <= {1'b1, tx_frame[9:1]}; tx_bit <= tx_bit + 1'b1; tx_timer <= divisor - 1'b1; end
                end
            end

            if (rx_enable) begin
                case (rx_state)
                    RX_IDLE: if (!rx_sync2) begin rx_state <= RX_START; rx_timer <= (divisor >> 1); end
                    RX_START: if (rx_timer != 0) rx_timer <= rx_timer - 1'b1;
                        else if (!rx_sync2) begin rx_state <= RX_DATA; rx_timer <= divisor - 1'b1; rx_bit <= 0; end
                        else rx_state <= RX_IDLE;
                    RX_DATA: if (rx_timer != 0) rx_timer <= rx_timer - 1'b1;
                        else begin
                            rx_shift[rx_bit] <= rx_sync2;
                            rx_timer <= divisor - 1'b1;
                            if (rx_bit == 7) rx_state <= RX_STOP;
                            else rx_bit <= rx_bit + 1'b1;
                        end
                    RX_STOP: if (rx_timer != 0) rx_timer <= rx_timer - 1'b1;
                        else begin
                            rx_state <= RX_IDLE;
                            if (!rx_sync2) framing_error <= 1;
                            else if (rx_full) overrun <= 1;
                            else begin rx_fifo[rx_wptr] <= rx_shift; rx_wptr <= rx_wptr + 1'b1; end
                        end
                endcase
            end else rx_state <= RX_IDLE;

            if (rx_pop) rx_rptr <= rx_rptr + 1'b1;
            case ({rx_push, rx_pop})
                2'b10: rx_count <= rx_count + 1'b1;
                2'b01: rx_count <= rx_count - 1'b1;
                default: ;
            endcase
        end
    end
endmodule
