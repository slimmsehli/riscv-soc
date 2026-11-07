# SoC Hardening Milestones

The six implementation milestones are complete. This follow-on list hardens verification and checks release readiness.

| # | Work item | Main deliverable | Exit criteria |
|---:|---|---|---|
| 7.1 | Seeded random tests and functional coverage | Reproducible randomized UART, DMA, I2C, and bus scenarios with coverage counters/bins | Multiple recorded seeds pass; required coverage bins are nonzero and reported |
| 7.2 | Lint and synthesis quality | Stronger lint, synthesis/elaboration checks, reviewed warnings | No unexplained design warnings or unsupported constructs; synthesis completes |
| 7.3 | Reset, stall, and boundary stress | Reset during active traffic, long stalls, address and transfer boundary cases | Tests terminate and recover correctly across supported corner cases |
| 7.4 | Release evidence and limitations | Updated design notes and reproducible verification report | Tool versions, commands, results, and known limitations are recorded |

## Current status

- **7.1 Complete** — UART, DMA, I2C, and fabric benches accept `+SEED=<decimal>`, print seeds and coverage bins, and the Makefile runs seeds 1, 42, and 2025 by default.
- 7.2–7.4 Pending

Run this item with `make clean && make uart-test dma-test i2c-test soc-fabric-test`. Override the deterministic seed matrix with `make ... SEEDS="7 19 1234"`. A seed run fails if its required functional bins are not hit.
