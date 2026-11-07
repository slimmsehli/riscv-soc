# DMA IP

`dma_ip.sv` provides the register interface and one-byte-at-a-time bus-master engine described in `SOC_SPEC.md`. The master emits aligned 32-bit bus addresses, uses byte write strobes for destination lanes, and extracts source bytes from the corresponding read lane. It preserves increasing-address copy order and reports a bus error through sticky ERROR status.

Run `make dma-test` for the self-checking Verilator simulation. Scenario logs report zero-length completion, unaligned copies with wait states and CPU contention, a deterministic length sweep (1, 2, 3, 4, 7, 15, 16, and 31 bytes), single-byte transfer, busy-start rejection, DONE/ERROR W1C behavior, and an injected bus error. Destination bytes are checked individually.
