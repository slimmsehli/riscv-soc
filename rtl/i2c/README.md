# I2C Master IP

`i2c_master.sv` implements the register interface in `SOC_SPEC.md`. The `i2c_scl_low` and `i2c_sda_low` outputs are open-drain controls: a value of 1 pulls the corresponding line low; 0 releases it. The controller supports standalone START, STOP, WRITE, and READ commands, with one command active at a time. Clock-high phases pause until sampled SCL is high.

Run `make i2c-test` for the Verilator test. It checks START/STOP, several write patterns, MSB-first byte read, ACK/NACK status, clock stretching, divider minimum clamping, unsupported overlapping commands, disabled-controller completion, and sticky status clearing. Since command opcodes overlap the low status bits, W1C uses extended write bits 8 (DONE) and 9 (ACK_ERROR), as documented in `SOC_SPEC.md`.
