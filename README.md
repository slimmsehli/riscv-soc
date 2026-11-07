# RISC-V SoC

A small RV32I system-on-chip implemented in SystemVerilog. It integrates the open-source PicoRV32 core with locally implemented UART, DMA, and I2C master IP, shared SRAM, and a CPU/DMA bus fabric. The project includes standalone IP testbenches and a C-driven, Verilator-based SoC simulation.

## Features

- PicoRV32 configured as an RV32I machine-mode core
- 64 KiB byte-write-enabled SRAM
- 32-bit peripheral bus with address decode and bounded CPU/DMA arbitration
- UART with transmit and receive FIFOs
- Memory-to-memory DMA with byte-accurate unaligned transfers
- Open-drain I2C master with clock-stretch support
- 16-pin GPIO with synchronized inputs and per-pin direction
- Freestanding RV32I C build and `$readmemh` program loading
- Seeded randomized tests, functional coverage bins, reset/stall/boundary checks, Verilator lint, Icarus elaboration, and Yosys synthesis checks

## Address map

| Region | Base | Size |
|---|---:|---:|
| SRAM | `0x0000_0000` | 64 KiB |
| UART | `0x1000_0000` | 4 KiB |
| DMA | `0x1000_1000` | 4 KiB |
| I2C master | `0x1000_2000` | 4 KiB |
| Simulation completion mailbox | `0x1000_3000` | Test use |
| GPIO | `0x1000_4000` | 4 KiB |

The full register definitions and bus contract are in [SOC_SPEC.md](SOC_SPEC.md).

## Get the source

PicoRV32 is tracked as a pinned Git submodule. Clone recursively so the core is present:

```sh
git clone --recurse-submodules <repository-url>
cd riscv-soc
```

If you already cloned without submodules:

```sh
git submodule update --init --recursive
```

## Tools

The current Makefile uses:

- Verilator with `--binary` and timing support
- GNU RISC-V GCC/binutils supporting `-march=rv32i -mabi=ilp32`
- Icarus Verilog for a second top-level elaboration check
- Yosys for memory inference and generic synthesis checks
- GNU make, Python 3, and a C++ compiler

Check `CORE_SETUP.md` for the pinned core revision and setup details.

## Build and run

Run the integrated C program in the SoC testbench:

```sh
make sim
```

The target compiles the RV32I software, converts it to the SRAM hex format, loads it into SRAM with `$readmemh`, and runs the SoC in Verilator. The testbench checks the UART signature, DMA destination bytes, I2C transactions, and software completion marker.

Run all unit, infrastructure, lint, elaboration, synthesis, and integration checks:

```sh
make clean
make core-smoke uart-test dma-test i2c-test gpio-test soc-sram-test soc-fabric-test soc-lint soc-iverilog soc-synth sim
```

UART, DMA, I2C, and fabric tests run seeds `1`, `42`, and `2025` by default. Override the set for a target, for example:

```sh
make dma-test SEEDS="7 19 1234"
```

Build outputs and Yosys logs go under `build/`.

## Project status

The six implementation milestones and current verification hardening plan are complete for RTL simulation and generic synthesis. See [SOC_MILESTONES.md](SOC_MILESTONES.md), [SOC_HARDENING_MILESTONES.md](SOC_HARDENING_MILESTONES.md), and [SOC_VERIFICATION_REPORT.md](SOC_VERIFICATION_REPORT.md) for details and results.

The next project phase is FPGA targeting. No board has been selected yet. FPGA work will need a board wrapper and constraints, SRAM block-RAM inference or mapping, and target-specific I2C pad handling and timing checks. Generic synthesis is not an FPGA timing or area result.

## License

The PicoRV32 core is distributed under the ISC license; see [`rtl/vendor/picorv32/COPYING`](rtl/vendor/picorv32/COPYING). The SoC RTL and software in this repository do not yet have a project-level license. Choose and add one before redistributing the project under a declared license.
