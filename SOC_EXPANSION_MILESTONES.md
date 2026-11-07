# MCU Peripheral Expansion Milestones

Implement and validate each block as a separate checkpoint. After each block is committed, pause for review before beginning the next one.

| # | IP block | Initial scope | Exit criteria |
|---:|---|---|---|
| 8.1 | GPIO | 16 synchronized inputs, 16 output values, per-pin direction, memory-mapped bus | Unit test, SoC register access, FPGA-facing pins, and full regression pass |
| 8.2 | SPI master | Configurable CPOL/CPHA, clock divider, chip select, 8-bit transfers, RX/TX status | Unit test for all four modes, loopback/behavioral target, SoC access, regression pass |
| 8.3 | Machine timer | 64-bit `mtime` and `mtimecmp` style timer registers, machine timer interrupt output | Counter, compare, rollover, and interrupt-pending behavior verified |
| 8.4 | Interrupt controller and CPU path | Enable PicoRV32 IRQ support; add prioritized external interrupt pending/enable/claim or equivalent small controller | Timer and peripheral interrupts reach and clear in firmware and testbench |
| 8.5 | Watchdog timer | Programmable timeout, service key, enable/lock policy, reset-cause status | Timeout reset, service, disable policy, and reset-cause tests pass |
| 8.6 | PWM | At least four channels with period/duty control and polarity | Boundary duty values, period update, and output timing tested |
| 8.7 | I2S | Selectable transmit or receive path, configurable word width and frame timing | Codec-style behavioral endpoint checks clocks, alignment, and sample sequence |
| 8.8 | CAN controller | Begin with Classical CAN; bit timing, arbitration, framing, ACK/error handling, FIFOs | Behavioral two-node test and documented external transceiver interface |
| 8.9 | USB device | Start with USB Full-Speed device mode and a narrow class/demo scope | Protocol and host interoperability validation with a PHY/interface selected |

USB host mode, USB High-Speed, CAN FD, and hardware-specific ADC/PHY functions are later extensions. They require a selected FPGA board and suitable external hardware or PHY.

## Workflow

For every row: specify the register and pin contract; implement RTL and isolated tests; validate lint, unit test, SoC integration, and full regression; document results; commit; then pause for review before proceeding.

## Current status

- **8.1 GPIO Complete** — standalone bus/pin tests and the integrated C test pass; all 16 pins are exposed at `soc_top`.
- 8.2–8.9 Pending
