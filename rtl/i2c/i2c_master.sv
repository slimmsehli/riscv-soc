module i2c_master (
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
    input  logic        i2c_scl_in,
    output logic        i2c_scl_low,
    input  logic        i2c_sda_in,
    output logic        i2c_sda_low
);
    typedef enum logic [3:0] {
        IDLE, START_HOLD, STOP_LOW, STOP_RISE,
        WRITE_SETUP, WRITE_HIGH, WRITE_ACK_SETUP, WRITE_ACK_HIGH,
        READ_SETUP, READ_HIGH, READ_ACK_SETUP, READ_ACK_HIGH
    } state_t;
    state_t state;
    logic [7:0] tx_data, rx_data;
    logic [7:0] shift_data;
    logic [3:0] bit_index;
    logic [31:0] divider, timer;
    logic enabled, busy, done, ack_error, ack_after_read;
    logic scl_low, sda_low;

    always_comb begin
        cfg_ready = cfg_valid;
        cfg_error = cfg_valid && (cfg_addr[1:0] != 0 || cfg_addr > 4'hc);
        cfg_rdata = 0;
        if (cfg_valid && !cfg_write) begin
            case (cfg_addr)
                4'h0: cfg_rdata = {24'b0, rx_data};
                4'h4: cfg_rdata = {29'b0, ack_error, done, busy};
                4'h8: cfg_rdata = divider;
                4'hc: cfg_rdata = {31'b0, enabled};
                default: cfg_rdata = 0;
            endcase
        end
    end

    assign i2c_scl_low = scl_low;
    assign i2c_sda_low = sda_low;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            tx_data <= 0; rx_data <= 0; shift_data <= 0; bit_index <= 0;
            divider <= 250; timer <= 0;
            enabled <= 1; busy <= 0; done <= 0; ack_error <= 0;
            ack_after_read <= 0; scl_low <= 0; sda_low <= 0;
        end else begin
            if (cfg_valid && cfg_ready && cfg_write && !cfg_error) begin
                case (cfg_addr)
                    4'h0: if (|cfg_wstrb) tx_data <= cfg_wdata[7:0];
                    4'h8: if (|cfg_wstrb) divider <= cfg_wdata < 4 ? 4 : cfg_wdata;
                    4'hc: if (cfg_wstrb[0]) enabled <= cfg_wdata[0];
                    4'h4: begin
                        // Extended W1C bits avoid collisions with STOP and WRITE opcodes.
                        if (cfg_wdata[8]) done <= 0;
                        if (cfg_wdata[9]) ack_error <= 0;
                        if (|cfg_wdata[3:0]) begin
                            if (busy) begin ack_error <= 1; end
                            else if (!enabled || $countones(cfg_wdata[3:0]) != 1) begin
                                done <= 1; ack_error <= 1;
                            end else begin
                                busy <= 1; done <= 0;
                                timer <= divider - 1'b1;
                                bit_index <= 0;
                                if (cfg_wdata[1]) begin state <= STOP_LOW; scl_low <= 1; sda_low <= 1; end
                                else if (cfg_wdata[2]) begin state <= WRITE_SETUP; scl_low <= 1; sda_low <= !tx_data[7]; shift_data <= tx_data; end
                                else if (cfg_wdata[3]) begin state <= READ_SETUP; scl_low <= 1; sda_low <= 0; shift_data <= 0; ack_after_read <= cfg_wdata[4]; end
                                else if (cfg_wdata[0]) begin state <= START_HOLD; scl_low <= 0; sda_low <= 0; end
                            end
                        end
                    end
                    default: ;
                endcase
            end

            if (busy) begin
                if (timer != 0) timer <= timer - 1'b1;
                else begin
                    case (state)
                        START_HOLD: begin
                            if (i2c_scl_in) begin
                                if (!sda_low) begin sda_low <= 1; timer <= divider - 1'b1; end
                                else begin state <= IDLE; busy <= 0; done <= 1; end
                            end else timer <= 0;
                        end
                        STOP_LOW: begin scl_low <= 0; state <= STOP_RISE; timer <= divider - 1'b1; end
                        STOP_RISE: if (i2c_scl_in) begin
                            sda_low <= 0; state <= IDLE; busy <= 0; done <= 1;
                        end else timer <= 0;
                        WRITE_SETUP: begin scl_low <= 0; state <= WRITE_HIGH; timer <= divider - 1'b1; end
                        WRITE_HIGH: if (i2c_scl_in) begin
                            scl_low <= 1;
                            if (bit_index == 7) begin state <= WRITE_ACK_SETUP; sda_low <= 0; end
                            else begin bit_index <= bit_index + 1'b1; shift_data <= {shift_data[6:0], 1'b0}; sda_low <= !shift_data[6]; state <= WRITE_SETUP; end
                            timer <= divider - 1'b1;
                        end else timer <= 0;
                        WRITE_ACK_SETUP: begin scl_low <= 0; state <= WRITE_ACK_HIGH; timer <= divider - 1'b1; end
                        WRITE_ACK_HIGH: if (i2c_scl_in) begin
                            if (i2c_sda_in) ack_error <= 1;
                            scl_low <= 1; state <= IDLE; busy <= 0; done <= 1;
                        end else timer <= 0;
                        READ_SETUP: begin scl_low <= 0; state <= READ_HIGH; timer <= divider - 1'b1; end
                        READ_HIGH: if (i2c_scl_in) begin
                            shift_data <= {shift_data[6:0], i2c_sda_in};
                            scl_low <= 1;
                            if (bit_index == 7) begin state <= READ_ACK_SETUP; rx_data <= {shift_data[6:0], i2c_sda_in}; end
                            else begin bit_index <= bit_index + 1'b1; state <= READ_SETUP; end
                            timer <= divider - 1'b1;
                        end else timer <= 0;
                        READ_ACK_SETUP: begin sda_low <= ack_after_read; scl_low <= 0; state <= READ_ACK_HIGH; timer <= divider - 1'b1; end
                        READ_ACK_HIGH: if (i2c_scl_in) begin
                            scl_low <= 1; sda_low <= 0; state <= IDLE; busy <= 0; done <= 1;
                        end else timer <= 0;
                        default: begin state <= IDLE; busy <= 0; done <= 1; ack_error <= 1; end
                    endcase
                end
            end
        end
    end
endmodule
