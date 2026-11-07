`timescale 1ns/1ps
module gpio_tb;
    logic clk=0, rst_n=0;
    always #5 clk=~clk;
    logic valid=0, write=0;
    logic [3:0] addr=0, wstrb=0;
    logic [31:0] wdata=0;
    logic [15:0] gpio_in=0;
    wire ready, error;
    wire [31:0] rdata;
    wire [15:0] gpio_out, gpio_oe;

    gpio_ip dut(.clk,.rst_n,.bus_valid(valid),.bus_ready(ready),.bus_addr(addr),
        .bus_write(write),.bus_wdata(wdata),.bus_wstrb(wstrb),.bus_rdata(rdata),
        .bus_error(error),.gpio_in,.gpio_out,.gpio_oe);

    task automatic wr(input logic [3:0] a,input logic [31:0] d,input logic [3:0] strobe);
        @(negedge clk); valid=1; write=1; addr=a; wdata=d; wstrb=strobe;
        @(posedge clk); #1;
        if (!ready || error) $fatal(1,"GPIO write error addr=%x",a);
        @(negedge clk); valid=0; write=0; wstrb=0;
    endtask

    task automatic rd(input logic [3:0] a,input logic [31:0] expected);
        @(negedge clk); valid=1; write=0; addr=a; #1;
        if (!ready || error || rdata != expected)
            $fatal(1,"GPIO read addr=%x got=%08x expected=%08x error=%b",a,rdata,expected,error);
        @(posedge clk); #1; @(negedge clk); valid=0;
    endtask

    initial begin
        repeat(4) @(negedge clk); rst_n=1;
        $display("GPIO scenario: reset defaults and synchronized input");
        if (gpio_out != 0 || gpio_oe != 0) $fatal(1,"GPIO reset defaults incorrect");
        gpio_in=16'ha55a; repeat(3) @(negedge clk); rd(0,32'ha55a);
        $display("GPIO scenario: output latch, direction, and byte strobes");
        wr(4,32'h000096c3,4'b0011);
        if (gpio_out != 16'h96c3 || gpio_oe != 0) $fatal(1,"output latch/direction mismatch");
        wr(8,32'h00000f0f,4'b0001);
        if (gpio_oe != 16'h000f) $fatal(1,"low-byte direction strobe mismatch %x",gpio_oe);
        wr(8,32'h0000a500,4'b0010);
        if (gpio_oe != 16'ha50f) $fatal(1,"high-byte direction strobe mismatch %x",gpio_oe);
        wr(4,32'h00001200,4'b0010);
        if (gpio_out != 16'h12c3) $fatal(1,"output byte update mismatch %x",gpio_out);
        rd(4,32'h12c3); rd(8,32'ha50f);
        $display("GPIO scenario: invalid address rejection");
        @(negedge clk); valid=1; addr=4'hc; #1;
        if (!ready || !error) $fatal(1,"GPIO invalid register did not error");
        @(posedge clk); #1; @(negedge clk); valid=0;
        $display("GPIO_TEST_PASS input=%04x output=%04x oe=%04x",gpio_in,gpio_out,gpio_oe);
        $finish;
    end
    initial begin #5000; $fatal(1,"GPIO timeout"); end
endmodule
