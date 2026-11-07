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

Yosys is not currently available in the environment, so synthesis has not yet been run. `make soc-iverilog` provides a second elaboration check, not a substitute for synthesis.
