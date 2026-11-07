module soc_reset_sync (
    input logic clk,
    input logic arst_n,
    output logic rst_n
);
    (* async_reg = "true" *) logic [1:0] sync_ff;
    always_ff @(posedge clk or negedge arst_n) begin
        if (!arst_n) sync_ff <= 2'b00;
        else sync_ff <= {sync_ff[0], 1'b1};
    end
    assign rst_n = sync_ff[1];
endmodule
