# UART IP

`uart_ip.sv` implements the UART register contract in `SOC_SPEC.md` with 16-byte TX/RX FIFOs and a single 32-bit peripheral bus transaction interface. The divisor is the number of system clocks per serial bit. The block is synchronous to `clk`; `rst_n` is active low. No interrupts are generated.

Run the self-checking Verilator test with `make uart-test`. It checks reset/register values, TX framing and bit order, RX data/order, FIFO empty/full and overrun, framing-error reporting, and RX/error clearing.
