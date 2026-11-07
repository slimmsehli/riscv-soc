RISCV_PREFIX ?= riscv64-unknown-elf-
CC := $(RISCV_PREFIX)gcc
OBJCOPY := $(RISCV_PREFIX)objcopy
VERILATOR ?= verilator
BUILD := build
CORE := rtl/vendor/picorv32/picorv32.v

.PHONY: core-smoke uart-test dma-test clean

core-smoke: $(BUILD)/Vcore_smoke
	$(BUILD)/Vcore_smoke

uart-test: $(BUILD)/Vuart_tb
	$(BUILD)/Vuart_tb

dma-test: $(BUILD)/Vdma_tb
	$(BUILD)/Vdma_tb

$(BUILD)/Vdma_tb: rtl/dma/dma_ip.sv tb/dma_tb.sv
	mkdir -p $(BUILD)
	$(VERILATOR) --binary --timing --top-module dma_tb -Wall -Wno-fatal \
		--Mdir $(BUILD)/dma_obj -o ../Vdma_tb $^

$(BUILD)/Vuart_tb: rtl/uart/uart_ip.sv tb/uart_tb.sv
	mkdir -p $(BUILD)
	$(VERILATOR) --binary --timing --top-module uart_tb -Wall -Wno-fatal \
		--Mdir $(BUILD)/uart_obj -o ../Vuart_tb $^

$(BUILD)/core_smoke.elf: sw/start.S sw/core_smoke.c sw/core_smoke.ld
	mkdir -p $(BUILD)
	$(CC) -march=rv32i -mabi=ilp32 -O1 -ffreestanding -fno-builtin -nostdlib -nostartfiles \
		-Wl,--build-id=none -Wl,-T,sw/core_smoke.ld -Wl,-Map,$(BUILD)/core_smoke.map \
		sw/start.S sw/core_smoke.c -o $@

$(BUILD)/core_smoke.hex: $(BUILD)/core_smoke.elf scripts/bin_to_hex.py
	$(OBJCOPY) -O binary $< $(BUILD)/core_smoke.bin
	python3 scripts/bin_to_hex.py $(BUILD)/core_smoke.bin $@

$(BUILD)/Vcore_smoke: $(CORE) tb/core_smoke.sv $(BUILD)/core_smoke.hex
	$(VERILATOR) --binary --timing --top-module core_smoke -Wall -Wno-fatal \
		--Mdir $(BUILD)/obj_dir -o ../Vcore_smoke $(CORE) tb/core_smoke.sv

clean:
	rm -rf $(BUILD)
