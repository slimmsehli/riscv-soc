OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 64K }
SECTIONS {
    . = ORIGIN(RAM);
    .text : { KEEP(*(.text.start)) *(.text*) } > RAM
    .rodata : { *(.rodata*) } > RAM
    .data : { *(.data*) } > RAM
    .bss : { *(.bss*) *(COMMON) } > RAM
    . = ALIGN(16);
    _stack_top = ORIGIN(RAM) + LENGTH(RAM);
    ASSERT(. < _stack_top, "program exceeds SRAM")
}
