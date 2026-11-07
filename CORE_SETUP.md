# Milestone 1: Core and Toolchain Setup

## Core selection

- Core: PicoRV32 by YosysHQ
- Upstream: https://github.com/YosysHQ/picorv32
- Vendored revision: `ef203c2b0a3fb793280f5114941416c425c5b461`
- License: ISC; see [`rtl/vendor/picorv32/COPYING`](rtl/vendor/picorv32/COPYING)
- Configuration for the smoke test: RV32I, no compressed instructions, multiply/divide or interrupts; reset vector `0x00000000`.

The core is tracked as a Git submodule pinned to the revision above. Clone this project with `git clone --recurse-submodules ...` (or run `git submodule update --init --recursive` after cloning) to retrieve it. Update the pin only by deliberately changing the submodule revision and reviewing upstream license and interface changes.

## Tools

The following tools are used by the current Makefile targets:

- Verilator 5.x with `--binary` and timing support
- GNU RISC-V toolchain with `riscv64-unknown-elf-gcc` and `riscv64-unknown-elf-objcopy`; the installed compiler must support `-march=rv32i -mabi=ilp32`
- GNU make, Python 3, and a C++ compiler for Verilator's generated model

Check versions with `verilator --version` and `riscv64-unknown-elf-gcc --version`. The `riscv64` prefix names the toolchain build; it supports RV32 output through the selected `-march` and `-mabi` options.

## Standalone smoke test

Run from the project root:

```sh
make core-smoke
```

The target compiles `sw/start.S` and `sw/core_smoke.c` as freestanding RV32I/ILP32, links at address zero, converts the ELF to a flat binary, and packs little-endian 32-bit words into `build/core_smoke.hex`. `tb/core_smoke.sv` loads that image using `$readmemh`, releases reset, and runs the upstream core against a small delayed SRAM model. A memory-mapped test completion address at `0x10000000` is provided by the harness. A passing run prints `CORE_SMOKE_PASS`; mismatches, traps, unexpected accesses, or timeout are fatal.

The smoke program uses a stack allocated at the top of a 64 KiB address range and exercises arithmetic, loop branches, subroutine call/return, stack operations, and data loads/stores. This is a core readiness check, not a full ISA compliance suite or SoC peripheral test.

## Current result

Validated with Verilator 5.051 devel, GNU RISC-V GCC 14.2.0, and GNU objcopy 2.45.50. `make core-smoke` completed with `CORE_SMOKE_PASS cycles=431 loads=100 stores=9`.

The spec's initial tool setup and standalone core smoke portion of milestone 1 is complete. Additional core functionality coverage can be added if required before SoC integration; peripheral milestones remain pending.
