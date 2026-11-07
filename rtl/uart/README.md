# UART IP

`uart_ip.sv` implements the UART register contract in `SOC_SPEC.md` with 16-byte TX/RX FIFOs and a single 32-bit peripheral bus transaction interface. The divisor is the number of system clocks per serial bit. The block is synchronous to `clk`; `rst_n` is active low. No interrupts are generated.

Run the self-checking Verilator test with `make uart-test`. The log identifies each scenario. Coverage includes reset/register values, TX framing and bit timing, TX FIFO full/clear, RX FIFO fill/order/wraparound, empty restoration, framing error, overrun, and sticky-error clearing.
