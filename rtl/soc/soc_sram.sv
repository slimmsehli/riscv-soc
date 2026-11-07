module soc_sram #(
    parameter integer WORDS = 16384,
    parameter INIT_FILE = ""
) (
    input logic clk,
    input logic rst_n,
    input logic valid,
    output logic ready,
    input logic [31:0] addr,
    input logic write,
    input logic [31:0] wdata,
    input logic [3:0] wstrb,
    output logic [31:0] rdata,
    output logic error
);
    logic [31:0] words [0:WORDS-1];
    integer lane;
    initial if (INIT_FILE != "") $readmemh(INIT_FILE, words);
    assign ready = valid;
    assign error = valid && (addr[1:0] != 0 || addr[31:16] != 0 || integer'(addr[15:2]) >= WORDS);
    always_comb begin
        if (valid && !error) rdata = words[addr[15:2]];
        else rdata = 0;
    end
    always_ff @(posedge clk) begin
        if (valid && ready && write && !error)
            for (lane = 0; lane < 4; lane = lane + 1)
                if (wstrb[lane]) words[addr[15:2]][lane*8 +: 8] <= wdata[lane*8 +: 8];
    end
endmodule
