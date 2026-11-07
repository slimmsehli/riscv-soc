RISCV_PREFIX ?= riscv64-unknown-elf-
CC := $(RISCV_PREFIX)gcc
OBJCOPY := $(RISCV_PREFIX)objcopy
VERILATOR ?= verilator
IVERILOG ?= iverilog
YOSYS ?= yosys
BUILD := build
CORE := rtl/vendor/picorv32/picorv32.v
SOC_RTL := $(CORE) rtl/uart/uart_ip.sv rtl/dma/dma_ip.sv rtl/i2c/i2c_master.sv \
	rtl/soc/soc_reset_sync.sv rtl/soc/soc_sram.sv rtl/soc/soc_bus_fabric.sv \
	rtl/soc/picorv32_bus_wrapper.sv rtl/soc/soc_top.sv
SEEDS ?= 1 42 2025

.PHONY: core-smoke uart-test dma-test i2c-test soc-fabric-test soc-sram-test soc-lint soc-iverilog soc-synth soc-sim sim clean

core-smoke: $(BUILD)/Vcore_smoke
	$(BUILD)/Vcore_smoke

uart-test: $(BUILD)/Vuart_tb
	@set -e; for seed in $(SEEDS); do $(BUILD)/Vuart_tb +SEED=$$seed; done

dma-test: $(BUILD)/Vdma_tb
	@set -e; for seed in $(SEEDS); do $(BUILD)/Vdma_tb +SEED=$$seed; done

i2c-test: $(BUILD)/Vi2c_tb
	@set -e; for seed in $(SEEDS); do $(BUILD)/Vi2c_tb +SEED=$$seed; done

soc-fabric-test: $(BUILD)/Vsoc_fabric_tb
	@set -e; for seed in $(SEEDS); do $(BUILD)/Vsoc_fabric_tb +SEED=$$seed; done

soc-sram-test: $(BUILD)/Vsoc_sram_tb
	$(BUILD)/Vsoc_sram_tb

soc-lint:
	$(VERILATOR) --lint-only --top-module soc_top -Wall \
		-Wno-DECLFILENAME -Wno-PINCONNECTEMPTY -Wno-GENUNNAMED -Wno-BLKSEQ \
		-Wno-UNUSEDSIGNAL -Wno-SYNCASYNCNET $(SOC_RTL)

soc-iverilog:
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -s soc_top -o $(BUILD)/soc_top.vvp $(SOC_RTL)

soc-synth:
	mkdir -p $(BUILD)
	$(YOSYS) -Q -l $(BUILD)/yosys_memory.log -p 'read_verilog -sv $(SOC_RTL); hierarchy -check -top soc_top; synth -top soc_top -run begin:coarse; check; stat' > /dev/null
	$(YOSYS) -Q -l $(BUILD)/yosys_soc.log -p 'read_verilog -sv $(SOC_RTL); chparam -set SRAM_WORDS 64 soc_top; hierarchy -check -top soc_top; synth -top soc_top; check; stat' > /dev/null
	@echo "Full-depth inference: $$(rg 'Number of memories:|Number of memory bits:|Found and reported' $(BUILD)/yosys_memory.log | tail -3 | tr '\n' ' ')"
	@echo "Reduced-depth generic synthesis: $$(rg 'Number of cells:|Found and reported' $(BUILD)/yosys_soc.log | tail -3 | tr '\n' ' ')"

soc-sim: $(BUILD)/Vsoc_tb
	$(BUILD)/Vsoc_tb

sim: soc-sim

$(BUILD)/Vsoc_fabric_tb: rtl/soc/soc_bus_fabric.sv tb/soc_fabric_tb.sv
	mkdir -p $(BUILD)
	$(VERILATOR) --binary --timing --top-module soc_fabric_tb -Wall -Wno-fatal \
		--Mdir $(BUILD)/soc_fabric_obj -o ../Vsoc_fabric_tb $^

$(BUILD)/Vsoc_sram_tb: rtl/soc/soc_sram.sv tb/soc_sram_tb.sv tb/sram_init.hex
	mkdir -p $(BUILD)
	$(VERILATOR) --binary --timing --top-module soc_sram_tb -Wall -Wno-fatal \
		--Mdir $(BUILD)/soc_sram_obj -o ../Vsoc_sram_tb rtl/soc/soc_sram.sv tb/soc_sram_tb.sv

$(BUILD)/soc_test.elf: sw/start.S sw/soc_test.c sw/core_smoke.ld
	mkdir -p $(BUILD)
	$(CC) -march=rv32i -mabi=ilp32 -O1 -ffreestanding -fno-builtin -nostdlib -nostartfiles \
		-Wl,--build-id=none -Wl,-T,sw/core_smoke.ld -Wl,-Map,$(BUILD)/soc_test.map \
		sw/start.S sw/soc_test.c -o $@

$(BUILD)/soc_test.hex: $(BUILD)/soc_test.elf scripts/bin_to_hex.py
	$(OBJCOPY) -O binary $< $(BUILD)/soc_test.bin
	python3 scripts/bin_to_hex.py $(BUILD)/soc_test.bin $@

$(BUILD)/Vsoc_tb: $(CORE) rtl/uart/uart_ip.sv rtl/dma/dma_ip.sv rtl/i2c/i2c_master.sv \
		rtl/soc/soc_reset_sync.sv rtl/soc/soc_sram.sv rtl/soc/soc_bus_fabric.sv \
		rtl/soc/picorv32_bus_wrapper.sv rtl/soc/soc_top.sv tb/soc_tb.sv $(BUILD)/soc_test.hex
	$(VERILATOR) --binary --timing --top-module soc_tb -Wno-fatal \
		--Mdir $(BUILD)/soc_obj -o ../Vsoc_tb $(CORE) $(filter %.sv,$^)

$(BUILD)/Vi2c_tb: rtl/i2c/i2c_master.sv tb/i2c_tb.sv
	mkdir -p $(BUILD)
	$(VERILATOR) --binary --timing --top-module i2c_tb -Wall -Wno-fatal \
		--Mdir $(BUILD)/i2c_obj -o ../Vi2c_tb $^

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
