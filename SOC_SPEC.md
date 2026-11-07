# RISC-V SoC RTL Specification

## 1. Purpose

Build a small, reproducible RISC-V system-on-chip in synthesizable RTL. The SoC integrates an open-source RISC-V core, on-chip memory, and locally developed UART, DMA, I2C, GPIO, and SPI peripheral IP. Each IP has an independent self-checking testbench, and an integrated SoC testbench boots a compiled C program loaded into memory from a hexadecimal file.

This document defines the required architecture, interfaces, register maps, software flow, verification, and completion criteria. Implementations may add features while preserving the interfaces and behavior specified here.

## 2. Baseline choices and scope

- **CPU:** [PicoRV32](https://github.com/YosysHQ/picorv32), an open-source RV32 core. Vendor a pinned upstream revision and retain its license and attribution. Instantiate it with a 32-bit data path and the standard `mem_valid`/`mem_ready` memory interface. Keep the core behind a wrapper so it can be replaced without changing the SoC fabric.
- **ISA/software ABI:** RV32I, machine mode, no compressed instructions, no multiply/divide extension. Build freestanding C with a matching `riscv32-unknown-elf` toolchain.
- **RTL language:** SystemVerilog, synthesizable RTL except for testbench code.
- **Interconnect:** A small, single-request-at-a-time, 32-bit ready/valid peripheral bus. The CPU wrapper adapts PicoRV32's memory interface to the bus. The DMA is a second bus master; a simple arbiter grants one master at a time and holds the grant until completion. No cache or virtual memory is required.
- **Clock/reset:** One clock domain. Active-low asynchronous reset input, synchronously deasserted internally. All bus and peripheral state resets deterministically.
- **Memory:** 64 KiB byte-addressable on-chip SRAM model/RTL at `0x0000_0000`–`0x0000_FFFF`, initialized by the simulation testbench from a `$readmemh` file. The same memory is used for program/data and DMA buffers. No external boot ROM is required.
- **Initial peripheral scope:** UART is a synthesizable transmitter and receiver. I2C is a single-controller master with open-drain signaling, standard-mode timing, and byte transfers. DMA performs memory-to-memory copies. GPIO provides synchronized inputs and outputs, and SPI provides a programmed four-mode master. These baseline features keep the first implementation tractable.

## 3. Top-level behavior

The CPU starts at address `0x0000_0000`. The SoC testbench loads the compiled program image into SRAM before releasing reset. A software program exercises UART output, DMA copy, I2C master transactions against a behavioral I2C target, GPIO registers, and SPI transfers against a behavioral SPI target. The testbench checks externally visible results and stops on a software success/failure marker or timeout.

Top-level module: `soc_top`.

Required ports:

| Port | Direction | Description |
|---|---|---|
| `clk` | input | System clock |
| `rst_n` | input | Active-low reset |
| `uart_rx` | input | UART receive pin, idle high |
| `uart_tx` | output | UART transmit pin, idle high |
| `gpio_in[15:0]` | input | 16 external GPIO inputs |
| `gpio_out[15:0]` | output | GPIO output values |
| `gpio_oe[15:0]` | output | GPIO output enables; 1=drive output, 0=input/high impedance at board wrapper |
| `spi_miso` | input | SPI target data into the master |
| `spi_mosi` | output | SPI master data to the target |
| `spi_sck` | output | SPI serial clock |
| `spi_cs_n[3:0]` | output | Four active-low SPI chip selects |
| `i2c_scl` | inout | Open-drain I2C clock; drive low or release |
| `i2c_sda` | inout | Open-drain I2C data; drive low or release |

The simulation harness may expose status signals through a test-only wrapper, but no simulation-only ports are required on the synthesizable top.

## 4. Address map

All addresses are byte addresses. Bus accesses are 32-bit aligned; byte enables support subword writes where applicable. Unmapped accesses return an error response and must not hang the CPU.

| Region | Base | Size | Notes |
|---|---:|---:|---|
| SRAM | `0x0000_0000` | 64 KiB | Executable/read-write, byte enables |
| UART | `0x1000_0000` | 4 KiB | Register interface below |
| DMA | `0x1000_1000` | 4 KiB | Register interface below |
| I2C | `0x1000_2000` | 4 KiB | Register interface below |
| GPIO | `0x1000_4000` | 4 KiB | 16-pin input/output/direction block |
| SPI | `0x1000_5000` | 4 KiB | SPI master register interface |

The decoder uses the high address bits and rejects addresses outside these windows. Peripheral registers occupy the first 16 bytes of each window; other offsets read as zero and writes have no effect (or return an access error, consistently documented and tested).

## 5. Common bus contract

The bus has `valid`, `ready`, `addr[31:0]`, `wdata[31:0]`, `wstrb[3:0]`, `write`, `rdata[31:0]`, and `error` signals. A request is accepted on a rising edge when `valid && ready`. The requester holds request fields stable until acceptance. A response completes that accepted request exactly once; the requester may not issue a second request until completion. Reads return `rdata`; failed/unmapped accesses assert `error` with the response. Address and control must not change while stalled.

The arbiter gives the CPU priority when both masters request simultaneously, but must not starve DMA: after at most 16 consecutive CPU grants while DMA is pending, grant DMA next. A granted transaction remains owned by its master through its response. DMA accesses use the same address decoder and SRAM as the CPU. DMA accesses to peripheral windows return an error; this avoids peripheral side effects as DMA source/destination in the baseline.

## 6. IP specifications

### 6.1 UART

Register offsets from `0x1000_0000`:

| Offset | Name | Access | Definition |
|---:|---|---|---|
| `0x00` | `DATA` | R/W | Write low byte to enqueue TX; read pops RX FIFO, returning byte in bits 7:0. Empty read returns zero. |
| `0x04` | `STATUS` | R | bit 0 TX busy; bit 1 TX FIFO full; bit 2 RX FIFO empty; bit 3 RX FIFO full; bit 4 RX overrun; bit 5 framing error. Error bits are sticky until cleared via `CTRL`. |
| `0x08` | `CTRL` | R/W | bit 0 TX enable; bit 1 RX enable; bit 2 clear TX FIFO; bit 3 clear RX FIFO and errors. |
| `0x0C` | `DIV` | R/W | Baud divisor. One bit period is `DIV` system clocks; reset value 868 (approximately 115200 baud at 100 MHz). Minimum legal value 2. |

Use independent 16-byte TX and RX FIFOs. TX frames are one start bit, 8 data bits LSB first, one stop bit. RX samples at the bit center and reports framing/overrun errors. Reset enables TX/RX, leaves TX idle high, and empties FIFOs. No interrupts are required in the baseline.

### 6.2 DMA

Register offsets from `0x1000_1000`:

| Offset | Name | Access | Definition |
|---:|---|---|---|
| `0x00` | `SRC` | R/W | Source byte address |
| `0x04` | `DST` | R/W | Destination byte address |
| `0x08` | `LEN` | R/W | Number of bytes to copy |
| `0x0C` | `CTRL_STATUS` | R/W | write bit 0=START; read bit 0=BUSY, bit 1=DONE, bit 2=ERROR. DONE/ERROR are write-one-to-clear. |

START when busy is ignored and sets ERROR. A zero length completes immediately. Transfers copy bytes in increasing address order and preserve all bytes, including unaligned starts and lengths. The implementation may optimize aligned words but must produce identical byte semantics. DMA reads and writes SRAM through the shared bus; bus errors terminate the transfer and set ERROR. DONE and ERROR remain set until cleared. Software must poll status before reprogramming. DMA must not overwrite its own registers (those accesses are errors by the bus contract).

### 6.3 I2C master

Register offsets from `0x1000_2000`:

| Offset | Name | Access | Definition |
|---:|---|---|---|
| `0x00` | `DATA` | R/W | Transmit byte on write; received byte on read |
| `0x04` | `CMD_STATUS` | R/W | write bit 0=START, bit 1=STOP, bit 2=WRITE, bit 3=READ, bit 4=ACK control for READ (1 sends ACK, 0 sends NACK); extended write bit 8 clears DONE and bit 9 clears ACK_ERROR. Read bit 0=BUSY, bit 1=DONE, bit 2=ACK_ERROR. |
| `0x08` | `DIV` | R/W | SCL half-period in system clocks; reset value 250 for 100 kHz at 50 MHz. Minimum legal value 4. |
| `0x0C` | `CTRL` | R/W | bit 0=enable |

The controller supports START, STOP, byte WRITE, and byte READ operations, one command at a time, with MSB-first data and ACK/NACK on the ninth clock. It must release SDA/SCL to represent logic high and only actively drive low. Include clock stretching by waiting while sampled SCL is low. START/STOP and data setup/hold timing derive from `DIV`. Unsupported or overlapping commands set an error and complete without hanging. There is no multi-controller arbitration or interrupt in the baseline.

### 6.4 GPIO

The first expansion GPIO block has 16 pins. Inputs pass through two clocked synchronizer stages. Reset configures all pins as inputs, clears output values, and does not drive external pins high. Direction bit 1 drives the corresponding output value; bit 0 leaves the pin in input mode.

| Offset | Name | Access | Definition |
|---:|---|---|---|
| `0x00` | `INPUT` | R | Synchronized pin values in bits 15:0; upper bits read zero |
| `0x04` | `OUTPUT` | R/W | Output latch in bits 15:0; upper bits ignored/read zero |
| `0x08` | `DIR` | R/W | 1=output, 0=input for each pin; reset value zero |

Writes honor the common bus byte strobes. The baseline has no GPIO interrupts, pull-up controls, or per-pin alternate functions.

### 6.5 SPI master

The SPI master performs one 8-bit, MSB-first transfer per command. It supports all four CPOL/CPHA modes, four active-low chip-select outputs, a programmable half-period divider, and one transmit/receive data register. The selected chip select is asserted only for the active transfer. Reset selects chip select 0, mode 0, divider 2, and idle-low SCK.

| Offset | Name | Access | Definition |
|---:|---|---|---|
| `0x00` | `DATA` | R/W | Write transmit byte; read last received byte in bits 7:0 |
| `0x04` | `CTRL_STATUS` | R/W | write bit 0=START, bit 1=clear DONE, bit 3=clear ERROR. Read bit 0=BUSY, bit 1=DONE, bit 2=RX_VALID (same sticky completion indication as DONE), bit 3=ERROR |
| `0x08` | `DIV` | R/W | SCK half-period in system clocks; minimum 2 |
| `0x0C` | `CONFIG` | R/W | bits 3:0 one-hot active chip select; bit 4=CPOL; bit 5=CPHA |

Writing a non-one-hot chip-select value sets ERROR. Transfers are byte-wide and polled; there is no FIFO, slave mode, interrupt, or continuous chip-select mode in this first version.

## 7. Reset values

Reset clears bus state, CPU-facing wrapper state, DMA state, FIFOs, I2C command state, SPI transfer state, and error/status flags. SRAM contents are not reset by RTL. In simulation, memory is initialized from the hex image before reset is released. UART and I2C output pins are released/high while idle; SPI chip selects are inactive and SCK is at its reset polarity. Reset behavior is covered by each relevant testbench.

## 8. Repository and build deliverables

Organize implementation so RTL, testbenches, software, and scripts are clearly separated. A suggested layout is:

```text
rtl/                 # SoC, CPU wrapper, bus, SRAM, UART, DMA, I2C
rtl/vendor/picorv32/ # Pinned upstream core and license
tb/                  # Per-IP tests and integrated SoC testbench
sw/                  # Startup/linker files and C test programs
scripts/              # Build/run helpers
build/                # Generated ELF, map, disassembly, hex, simulator products
```

Provide a single documented command (for example, `make sim`) that builds software, converts the ELF to a memory hex image, builds RTL simulation, and runs the SoC test. Provide individual commands/targets for each IP test. Generated files belong under `build/` and should not be required as checked-in inputs.

Software compilation flow:

1. Compile startup assembly and freestanding C for RV32I, e.g. `-march=rv32i -mabi=ilp32 -ffreestanding -nostdlib`.
2. Link using a linker script placing `.text`, `.rodata`, `.data`, and `.bss` in the 64 KiB SRAM, with entry point at `0x0000_0000`; initialize stack near the top of SRAM and zero `.bss` in startup code.
3. Convert the ELF to a `$readmemh`-compatible image with a documented byte/word ordering. The image must fit SRAM; fail the build if it does not.
4. The Verilog/SystemVerilog SoC testbench calls `$readmemh` on the generated image to initialize the SRAM array before releasing reset. The memory model and image-generation script must agree on endianness and address-to-array indexing.

## 9. Verification requirements

All tests are self-checking, deterministic, and terminate with a nonzero failure status on error or timeout. Testbenches should use a common clock/reset convention and print a clear pass/fail summary. Do not rely on waveform inspection for pass criteria.

### UART testbench

- Register read/write, reset defaults, FIFO empty/full behavior and clear behavior.
- Transmit at least two bytes; decode `uart_tx` independently and check framing, bit order, and divisor timing.
- Drive valid RX frames and check FIFO data/order; test bad stop bit, overrun, and status clearing.
- Exercise bus stalls and verify stable requests/responses.

### DMA testbench

- Copy aligned and unaligned ranges, lengths 0, 1, and multiple bytes; verify all destination bytes and untouched guard bytes.
- Check busy/done/error behavior, write-one-to-clear, START while busy, and bus error handling.
- Contend CPU and DMA requests; verify data integrity and bounded arbitration progress.

### I2C testbench

- Connect a behavioral open-drain target with pull-ups; verify START/STOP, address/data bit order, ACK and NACK, reads, and repeated command sequencing.
- Test clock stretching, disabled controller, invalid/overlapping command, and status clearing.
- Check that neither master nor target actively drives the bus high.

### GPIO testbench

- Verify reset direction/output values, synchronized input reads, independent pin directions, byte strobes, and bus errors.

### SPI testbench

- Exercise all four CPOL/CPHA modes with a behavioral target, check byte ordering and all chip selects, and verify divider clamp, status, and invalid configuration handling.

### Integrated SoC testbench

- Load the software hex image into SRAM with `$readmemh`, then release reset and wait for a bounded completion timeout.
- Run a C program from address zero. It must transmit a UART signature; perform a DMA copy and verify memory; issue I2C write/read against a behavioral target; access GPIO; transfer SPI data against a behavioral target; and report success/failure through a documented test-only completion mechanism (e.g. a dedicated simulation address or wrapper signal).
- Independently check UART pin output, DMA result, I2C bus transactions, GPIO outputs, SPI pin/data results, and completion status. A software success marker alone is insufficient.
- Include at least one negative/error path in peripheral unit tests. The integrated test must fail on timeout, bus error, incorrect output, or incorrect memory contents.

## 10. Completion criteria

The SoC is complete when:

1. All RTL modules compile with the selected simulator and the CPU core is the pinned upstream open-source implementation.
2. UART, DMA, and I2C are locally implemented RTL and pass their independent self-checking testbenches.
3. `soc_top` integrates the CPU, arbiter/interconnect, SRAM, and all peripherals at the specified addresses.
4. Freestanding C compiles and links for the selected core; the resulting image is loaded by the Verilog testbench with `$readmemh` and executes from SRAM.
5. The top-level SoC testbench passes all specified end-to-end checks and has bounded timeouts.
6. Build/run commands, tool prerequisites, core revision/license, register map, and known limitations are documented.

## 11. Explicit non-goals for the first version

Interrupt controller, caches, MMU, privilege modes beyond machine mode, external DRAM, operating system, multi-channel DMA, I2C slave mode, UART parity/variable frame formats, bus bursts, and FPGA board constraints are outside the baseline. Keep module boundaries suitable for later extensions.
