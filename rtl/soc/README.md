# SoC Infrastructure

`picorv32_bus_wrapper.sv` adapts the PicoRV32 memory port to the common SoC request/response bus. `soc_bus_fabric.sv` decodes the 64 KiB SRAM and three peripheral windows, routes responses, rejects DMA peripheral accesses, and limits consecutive CPU grants under DMA contention. `soc_sram.sv` implements byte-write-enabled 64 KiB SRAM with optional `$readmemh` initialization. `soc_reset_sync.sv` asynchronously asserts reset and synchronizes deassertion. `soc_top.sv` wires these blocks to the CPU and completed peripheral IPs.

Verification targets:

- `make soc-sram-test`: `$readmemh` initialization, reads, byte writes, unaligned/out-of-range errors.
- `make soc-fabric-test`: address decode, unmapped errors, DMA peripheral rejection, stalled-request ownership, and CPU/DMA fairness.
- `make soc-lint`: whole-top Verilator `-Wall` lint. Waivers are limited to reviewed upstream style/debug signals, intentionally open optional core pins, and the asynchronous-assert/synchronous-release reset pattern.
- `make soc-iverilog`: independent SystemVerilog top elaboration with Icarus Verilog.
- `make soc-synth`: Yosys full-depth memory inference/check, plus complete generic SoC synthesis with a reduced 64-word SRAM to avoid mapping 64 KiB of behavioral SRAM into generic flip-flops. Logs are kept under `build/`.
- `make sim`: compile `sw/soc_test.c` for RV32I, link at SRAM address zero, convert to little-endian word hex, load it through `$readmemh`, and run the complete SoC in Verilator.

UART, DMA, I2C, and fabric tests run with deterministic seeds 1, 42, and 2025 by default. Override with `make dma-test SEEDS="7 19 1234"`. Test logs include scenario labels, seed values, and functional bin counts; each run fails if a required bin is empty.

The seeded regression also injects reset during active UART, DMA, I2C, and fabric operations; holds shared-bus requests stalled for 32 clocks; and attempts a DMA read across the SRAM limit to verify error termination.

The SRAM image uses one 32-bit hexadecimal word per line, with byte zero in bits 7:0, matching `scripts/bin_to_hex.py`. The integration program checks a UART signature, performs and verifies an unaligned DMA copy, and writes/reads a byte through the I2C master. It writes success/failure markers to the simulation completion mailbox at `0x10003000`; this address is reserved for simulation reporting. The top testbench independently checks transmitted UART bytes, copied SRAM contents, and I2C pin transactions.
