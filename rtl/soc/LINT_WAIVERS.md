# Whole-top lint waivers

`make soc-lint` enables Verilator `-Wall` and treats warnings as fatal (the default behavior when `-Wno-fatal` is absent). The following warning groups are waived for reviewed reasons:

| Warning | Reason |
|---|---|
| `DECLFILENAME` | The pinned PicoRV32 source intentionally contains helper modules in its upstream source file. |
| `PINCONNECTEMPTY` | Optional PicoRV32 look-ahead, PCPI, IRQ completion, and trace outputs are intentionally unused by this configuration. |
| `GENUNNAMED`, `BLKSEQ` | Existing upstream PicoRV32 coding style. The vendored source is kept unmodified. |
| `UNUSEDSIGNAL` | PicoRV32's internal debug aliases are not consumed in this integration. A separate lint inventory confirmed no local RTL unused-signal warning remains. |
| `SYNCASYNCNET` | The reset synchronizer uses asynchronous assertion and synchronized deassertion by design. |

New warning categories remain fatal. Recheck this table when the core, lint version, or integration changes.

`make soc-synth` checks memory inference at the specified 16K-word depth without mapping it (525,312 inferred memory bits across SRAM and UART FIFOs), then runs complete generic synthesis with a 64-word SRAM. Both Yosys `check` passes report zero problems. The reduced-depth run validates integrated control logic and tool compatibility; it is not a physical SRAM macro mapping or an area/timing result for the 64 KiB implementation. Yosys reports expected limitations for behavioral tri-state I2C pins and maps small UART FIFOs to registers.
