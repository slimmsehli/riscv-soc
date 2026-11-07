`timescale 1ns/1ps
module spi_tb;
    logic clk=0, rst_n=0;
    always #5 clk=~clk;
    logic valid=0, write=0;
    logic [3:0] addr=0, wstrb=0;
    logic [31:0] wdata=0;
    logic miso=0;
    wire ready, error, mosi, sck;
    wire [31:0] rdata;
    wire [3:0] cs_n;
    logic mode_cpol=0, mode_cpha=0;
    logic [7:0] target_rx=0;
    logic [7:0] observed_tx=0;
    integer sample_count=0, drive_count=0;

    spi_master dut(.clk,.rst_n,.bus_valid(valid),.bus_ready(ready),.bus_addr(addr),
        .bus_write(write),.bus_wdata(wdata),.bus_wstrb(wstrb),.bus_rdata(rdata),.bus_error(error),
        .spi_miso(miso),.spi_mosi(mosi),.spi_sck(sck),.spi_cs_n(cs_n));

    task automatic wr(input logic [3:0] a,input logic [31:0] d);
        @(negedge clk); valid=1; write=1; addr=a; wdata=d; wstrb=15;
        @(posedge clk); #1;
        if (!ready || error) $fatal(1,"SPI bus write failed addr=%x",a);
        @(negedge clk); valid=0; write=0; wstrb=0;
    endtask
    task automatic rd(input logic [3:0] a,output logic [31:0] d);
        @(negedge clk); valid=1; write=0; addr=a; #1;
        if (!ready || error) $fatal(1,"SPI bus read failed addr=%x",a);
        d=rdata;
        @(posedge clk); #1; @(negedge clk); valid=0;
    endtask
    task automatic transfer(input logic [7:0] tx,input logic [7:0] rx,
                            input logic cpol,input logic cpha,input logic [3:0] select_mask);
        logic [31:0] status, rx_word;
        integer waits;
        mode_cpol=cpol; mode_cpha=cpha; target_rx=rx; miso=rx[7];
        observed_tx=0; sample_count=0; drive_count=0;
        wr(12,{26'b0,cpha,cpol,select_mask});
        wr(0,tx);
        wr(4,1);
        waits=0;
        do begin rd(4,status); waits=waits+1; if(waits>80) $fatal(1,"SPI timeout mode=%0d%0d",cpol,cpha); end
        while(status[0]);
        rd(0,rx_word);
        if(rx_word[7:0] != rx) $fatal(1,"SPI RX mode=%0d%0d expected=%02x got=%02x",cpol,cpha,rx,rx_word[7:0]);
        if(observed_tx != tx || sample_count != 8)
            $fatal(1,"SPI TX mode=%0d%0d expected=%02x got=%02x samples=%0d",cpol,cpha,tx,observed_tx,sample_count);
        if(cs_n != 4'hf || sck != cpol) $fatal(1,"SPI did not return to idle");
        if(!status[1] || status[3]) $fatal(1,"SPI status mode=%0d%0d status=%x",cpol,cpha,status);
        $display("  SPI mode CPOL=%0d CPHA=%0d CS=%b TX=%02x RX=%02x passed",cpol,cpha,select_mask,tx,rx);
        wr(4,2); // clear DONE
    endtask

    always @(sck) begin
        // The DUT may release CS in the same delta cycle as its final
        // trailing edge. Count that final edge using the pre-release context.
        if (rst_n && (cs_n != 4'hf || (sample_count == 7 && sck == mode_cpol))) begin
            if ((!mode_cpha && (sck != mode_cpol)) || (mode_cpha && (sck == mode_cpol))) begin
                observed_tx = {observed_tx[6:0],mosi};
                sample_count = sample_count + 1;
            end else if (mode_cpha) begin
                if (drive_count < 8) miso = target_rx[7-drive_count];
                drive_count = drive_count + 1;
            end else if (sample_count < 8) begin
                miso = target_rx[7-sample_count];
            end
        end
    end

    logic [31:0] value;
    initial begin
        repeat(4) @(negedge clk); rst_n=1;
        $display("SPI scenario: reset defaults and divider clamp");
        rd(8,value); if(value!=2) $fatal(1,"SPI reset divider=%0d",value);
        wr(8,1); rd(8,value); if(value!=2) $fatal(1,"SPI divider min clamp failed");
        $display("SPI scenario: all CPOL/CPHA modes and distinct chip selects");
        transfer(8'ha5,8'h3c,0,0,4'b0001);
        transfer(8'h96,8'h69,0,1,4'b0010);
        transfer(8'hf0,8'h0f,1,0,4'b0100);
        transfer(8'h81,8'h7e,1,1,4'b1000);
        $display("SPI scenario: invalid multi-select configuration reports error");
        wr(12,{26'b0,2'b00,4'b0011});
        rd(4,value);
        if(!value[3]) $fatal(1,"SPI invalid CS configuration did not set error");
        wr(4,8); rd(4,value);
        if(value[3]) $fatal(1,"SPI error clear failed");
        $display("SPI_TEST_PASS");
        $finish;
    end
    initial begin #100000; $fatal(1,"SPI timeout"); end
endmodule
