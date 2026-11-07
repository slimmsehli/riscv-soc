# SoC Verification and Hardening Report

**Run date:** 2026-11-07 18:22 UTC  
**Repository revision:** `8bea6e1` (`hardening 7.3: stress resets stalls and boundaries`)  
**Result:** All listed regression, lint, elaboration, and synthesis checks passed.

## Tool versions

| Tool | Version |
|---|---|
| Verilator | 5.051 devel, revision `v5.050-49-g974020348` |
| Yosys | 0.52, commit `fee39a3284c90249e1d9684cf6944ffbbcbb8f90` |
| Icarus Verilog | 12.0 stable |
| RISC-V GCC | `riscv64-unknown-elf-gcc` 14.2.0 |
| GNU objcopy | 2.45.50 |

## Reproduction

Initialize the pinned PicoRV32 submodule when cloning:

```sh
git clone --recurse-submodules <repository>
```

Run the full simulation, seeded regression, lint, elaboration, and synthesis checks from the project root:

```sh
make clean
make core-smoke uart-test dma-test i2c-test soc-sram-test soc-fabric-test soc-lint soc-iverilog soc-synth sim
```

The IP and fabric tests run seeds `1`, `42`, and `2025` by default. To change them, pass `SEEDS="7 19 1234"` to the relevant make targets. Test output reports each seed, scenario, and required functional bin counts.

## Results

- PicoRV32 RV32I C smoke program boots and completes.
- UART seeds 1, 42, and 2025 pass RX data bins, FIFO, framing, overrun, and active-TX reset scenarios.
- DMA seeds 1, 42, and 2025 pass transfer length and alignment bins, wait-state/contention checks, reset while stalled, injected errors, and SRAM-boundary crossing.
- I2C seeds 1, 42, and 2025 pass data-pattern coverage, read/write, ACK/NACK, stretching, invalid-command, and reset-during-START scenarios.
- SRAM initialization, byte writes, alignment, and bounds checks pass.
- Fabric decode, error routing, fairness, seeded SRAM-bank accesses, 32-cycle stalls, and reset during stalled ownership pass.
- Strict Verilator top lint passes with the reviewed waivers in `rtl/soc/LINT_WAIVERS.md`.
- Icarus top elaboration exits successfully. Icarus prints “constant selects in always_* processes are not currently supported” notices for supported constructs; these are tool limitations, not elaboration failures.
- Yosys full-depth coarse synthesis retains two memories totaling 525,312 bits and reports zero `check` problems. Complete generic synthesis with a 64-word SRAM reports zero `check` problems.
- Integrated C-driven SoC simulation reports `SOC_TEST_PASS`, checks 18 UART bytes, all 13 DMA destination bytes, and I2C start/stop/read activity.

Detailed Yosys logs are generated under `build/yosys_memory.log` and `build/yosys_soc.log` by `make soc-synth`.

## Known limits

- The 64 KiB SRAM has been inferred at full depth but has not been mapped to a technology SRAM macro. The complete generic gate synthesis uses a reduced 64-word SRAM so it can finish quickly; it is not an area or timing estimate for a physical implementation.
- Yosys warns that its behavioral tri-state support is limited. An FPGA or ASIC integration must map the I2C open-drain release controls to the target's I/O primitives and verify pad behavior.
- Yosys maps the small UART FIFOs to registers. No target-specific memory optimization has been applied.
- The CPU wrapper reports bus errors to the core as an illegal instruction response because PicoRV32's native memory interface has no separate error input. A production software exception policy needs a documented trap handler or a core/bus adapter with explicit access-fault signaling.
- The design remains a single-clock, machine-mode RV32I system. There are no interrupts, cache, MMU, I2C multi-controller arbitration, DMA bursts, board constraints, or physical timing closure.

## Sign-off

Hardening items 7.1–7.4 are complete for the simulation and generic synthesis scope above. Physical SRAM mapping, board pad integration, and timing closure remain outside this sign-off.
