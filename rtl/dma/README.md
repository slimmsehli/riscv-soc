# DMA IP

`dma_ip.sv` provides the register interface and one-byte-at-a-time bus-master engine described in `SOC_SPEC.md`. The master emits aligned 32-bit bus addresses, uses byte write strobes for destination lanes, and extracts source bytes from the corresponding read lane. It preserves increasing-address copy order and reports a bus error through sticky ERROR status.

Run `make dma-test` for the self-checking Verilator simulation. The test checks zero and one byte lengths, an unaligned multi-byte copy, busy-start rejection, DONE/ERROR W1C behavior, injected bus errors, and shared-bus progress while a CPU-side requester contends.
