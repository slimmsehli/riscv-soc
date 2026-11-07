# RISC-V SoC Milestone Chart

This plan turns the requirements in [SOC_SPEC.md](SOC_SPEC.md) into six implementation milestones. Each milestone has a reviewable deliverable and exit criteria; later work depends on the earlier milestones passing.

## Overview

| # | Milestone | Main outcome | Sign-off |
|---:|---|---|---|
| 1 | RISC-V core and toolchain readiness | **Complete** — pinned core, working Verilator and RISC-V software flow, standalone core smoke program | Core boots and passes software checks |
| 2 | UART IP | **Complete** — UART RTL and self-checking Verilator testbench | UART behavior validated and signed off |
| 3 | DMA IP | **Complete** — DMA RTL and self-checking Verilator testbench | DMA behavior validated and signed off |
| 4 | I2C master IP | **Complete** — I2C master RTL and self-checking Verilator testbench | I2C behavior validated and signed off |
| 5 | SoC infrastructure | **Complete** — SRAM, interconnect, decode, arbitration, CPU wrapper, reset, and top-level wiring | Infrastructure tests and interfaces ready for assembly |
| 6 | Integrated SoC | **Complete** — core, memory, and IPs boot and run C software in Verilator | End-to-end software and pin-level checks pass |
| 7 | [Hardening work](SOC_HARDENING_MILESTONES.md) | **Complete** | Seeded coverage, stronger RTL checks, corner-case stress, release evidence |

## Milestone 1 — Core, tools, and standalone readiness

**Work**

- Select and pin the open-source RISC-V core specified by the project (PicoRV32 baseline); record its source revision and preserve its license and attribution.
- Obtain the core and required source collateral, including configuration files, example integration material, and any required simulation collateral.
- Set up Verilator and the `riscv32-unknown-elf` compiler/binutils needed for RV32I software. Record tool versions and reproducible setup/build commands.
- Create a standalone core harness with clock, reset, and a minimal memory model or supported core test setup.
- Write and compile a new freestanding C `main` program for the core. Exercise basic arithmetic/control flow, loads and stores, branches, stack use, and a completion/failure mechanism observable by the harness.
- Run the program in Verilator and retain build logs or a concise run report.

**Deliverables**

- Pinned core source and license notice.
- Documented tool prerequisites and version information.
- Standalone harness and source for the new test program.
- Reproducible command that compiles, runs, and reports pass/fail.

**Exit criteria**

- The core compiles in Verilator without unresolved warnings treated as errors or unexplained suppressions.
- The C program compiles for the selected ISA/ABI, starts at the intended reset address, and reaches its success marker.
- The harness observes expected load/store activity and reports failure on an incorrect result or timeout.
- Core configuration, reset behavior, memory interface, and any required wrapper assumptions are recorded for SoC integration.

## Milestone 2 — UART IP and sign-off

**Work**

- Implement the UART register block, TX/RX datapaths, baud divisor, and FIFOs as specified in `SOC_SPEC.md`.
- Build a self-checking SystemVerilog testbench and run it with Verilator.
- Validate register accesses, reset defaults, TX framing and timing, RX sampling and ordering, FIFO boundaries, and error/status clearing.
- Exercise stalled bus transactions and check request stability and response behavior.

**Deliverables**

- Synthesizable UART RTL and register documentation.
- Verilator testbench, run target/script, and test summary.
- UART sign-off record with simulator/tool versions and any known limitations.

**Exit criteria / sign-off**

- All required directed tests pass, including TX and RX pin-level checks, FIFO full/empty conditions, framing error, overrun, and reset.
- Tests have bounded timeouts and fail with a nonzero result on mismatch.
- No known blocking functional issue remains; register behavior matches the specification.

## Milestone 3 — DMA IP and sign-off

**Work**

- Implement DMA control/status registers and a bus-master transfer engine per `SOC_SPEC.md`.
- Support byte-accurate copies for aligned and unaligned addresses and arbitrary lengths within SRAM.
- Add a self-checking Verilator testbench with a memory/bus model and controllable stalls/errors.
- Validate zero-length, single-byte, multi-byte, busy/done/error status, write-one-to-clear, start-while-busy, and bus-error handling.
- Test contention with another requester and verify bounded arbitration progress once the arbiter is available; use a representative arbitration model before then.

**Deliverables**

- Synthesizable DMA RTL and register documentation.
- Verilator testbench and reproducible run target/script.
- DMA sign-off record with results and known limitations.

**Exit criteria / sign-off**

- Source and destination bytes match for aligned and unaligned transfers; guard bytes remain unchanged.
- Error and completion states follow the register contract and clear correctly.
- No transaction hangs; bus errors terminate the transfer and report ERROR.
- All tests are self-checking, bounded, and pass in Verilator.

## Milestone 4 — I2C master IP and sign-off

**Work**

- Implement the single-controller open-drain I2C master, timing divider, command/status registers, and clock-stretch handling per `SOC_SPEC.md`.
- Build a behavioral open-drain I2C target in a self-checking testbench; run the IP test in Verilator.
- Validate START/STOP, byte write/read, bit ordering, ACK/NACK, repeated operation sequencing, disabled and invalid commands, status clearing, and clock stretching.
- Check that the controller only pulls SCL/SDA low and releases them for logic high.

**Deliverables**

- Synthesizable I2C master RTL and register/timing documentation.
- Verilator testbench with behavioral target and run target/script.
- I2C sign-off record with results and known limitations.

**Exit criteria / sign-off**

- Pin-level bus transactions match the expected START, STOP, data, and ACK/NACK sequence.
- Clock stretching is handled without losing transaction state or hanging.
- Open-drain behavior, reset, disabled operation, and error/status behavior pass.
- All tests are self-checking, bounded, and pass in Verilator.

## Milestone 5 — SoC infrastructure

**Work**

- Implement the 64 KiB SRAM and simulation initialization support required by `SOC_SPEC.md`.
- Implement the shared 32-bit bus, CPU memory-interface wrapper, address decoder, response/error handling, and CPU/DMA arbitration.
- Integrate the peripheral register interfaces and check the specified address map.
- Add reset synchronization/deassertion and top-level pin wiring, including open-drain I2C handling.
- Add infrastructure-level tests for memory byte enables, address decode, unmapped access errors, bus stalls, arbitration ownership/fairness, and reset.
- Define the software image format and verify byte/word ordering between conversion script, SRAM indexing, and `$readmemh`.

**Deliverables**

- Synthesizable memory, bus, wrapper, decoder, arbitration, and reset RTL.
- Infrastructure testbenches and documented bus/address-map interfaces.
- Memory-image conversion procedure compatible with the SoC testbench's `$readmemh` loading.

**Exit criteria**

- CPU and DMA can access SRAM through the shared fabric without corruption or duplicate responses.
- All mapped peripherals are selected at the specified addresses; unmapped and prohibited DMA peripheral accesses complete with errors rather than hanging.
- Arbitration honors transaction ownership and makes progress for both CPU and DMA under contention.
- SRAM initialization format, endianness, and bounds are demonstrated with a small known image.
- Infrastructure tests pass with bounded timeouts.

## Milestone 6 — Full SoC assembly and C software test

**Work**

- Assemble the core, wrapper, SRAM, bus/interconnect, UART, DMA, and I2C into `soc_top`.
- Add startup code and a linker script for RV32I software running from address zero in SRAM; initialize stack and `.bss`.
- Write a C integration program that exercises UART output, DMA copy and memory verification, and I2C write/read against the testbench target.
- Compile and link the C program, convert the ELF to the documented hex format, and have the Verilog/SystemVerilog testbench load it into SRAM using `$readmemh` before releasing reset.
- Run the complete simulation in Verilator. Independently check UART output, DMA memory results, I2C bus activity/data, and the program completion status.
- Provide one documented command to build software, build simulation, and run the end-to-end test; retain logs and tool versions for the release record.

**Deliverables**

- Integrated `soc_top` and top-level Verilator testbench.
- Startup/linker files, C integration test, and reproducible ELF-to-hex flow.
- End-to-end run target/script and sign-off report.

**Exit criteria / final sign-off**

- The compiled C program is loaded by `$readmemh`, starts at address zero, and completes within a bounded timeout.
- UART signature and I2C transactions match expected values at the pins; DMA produces the expected SRAM contents and preserves guard data.
- Any bus error, mismatch, or timeout causes a nonzero test failure.
- All IP unit tests and infrastructure tests remain passing with the integrated design.
- Build prerequisites, commands, core revision/license, address map, and known limitations are documented.

## Sign-off record template

Complete this section for each milestone before marking it done.

| Field | Record |
|---|---|
| Milestone and date | |
| RTL/software revision | |
| Verilator version and command | |
| RISC-V toolchain version (where applicable) | |
| Tests run and result | |
| Open issues / accepted limitations | |
| Sign-off owner | |
