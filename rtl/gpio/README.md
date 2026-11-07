# GPIO IP

`gpio_ip.sv` implements 16 synchronized inputs, a 16-bit output latch, and per-pin direction control. Reset clears outputs and selects input mode. Register offsets and byte-strobe behavior are documented in `SOC_SPEC.md`.

Run `make gpio-test` for reset, input synchronization, output/direction controls, byte writes, and invalid-register checks. The integrated C test also reads the GPIO input pins and drives a known output pattern.
