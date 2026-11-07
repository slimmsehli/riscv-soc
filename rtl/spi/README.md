# SPI master IP

`spi_master.sv` implements a programmed, single-byte SPI master on the SoC's 32-bit peripheral bus. It supports MSB-first transfers in all four CPOL/CPHA modes, four active-low chip selects, and a programmable SCK half-period divider. There is no FIFO or interrupt; software polls completion.

## Registers

Base address: `0x1000_5000`. Register offsets are byte offsets.

| Offset | Name | Access | Definition |
|---:|---|---|---|
| `0x00` | DATA | R/W | Write the transmit byte; read the last received byte in bits 7:0. |
| `0x04` | CTRL_STATUS | R/W | Write bit 0 to start, bit 1 to clear DONE, or bit 3 to clear ERROR. Read bit 0=BUSY, bit 1=DONE, bit 2=RX_VALID (same sticky indication as DONE), bit 3=ERROR. |
| `0x08` | DIV | R/W | SCK half-period in system clocks. Values below 2 are clamped to 2. |
| `0x0C` | CONFIG | R/W | Bits 3:0 select exactly one active-low CS output; bit 4=CPOL; bit 5=CPHA. |

The selected CS is active only while a transfer is in progress. SCK returns to CPOL idle after completion. MOSI keeps the final bit stable through the last sampling edge. Invalid multi-select or zero-select configuration sets ERROR. Starting while busy sets ERROR without disturbing the active transfer.

## Validation

Run `make spi-test` for register, divider clamp, status/error, four-mode, four-CS, and behavioral-target checks. The integrated C firmware also transfers a byte against a testbench SPI target; `make sim` checks both TX pins and received data.
