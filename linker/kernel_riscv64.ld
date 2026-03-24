/* RISC-V 64 裸 ELF：QEMU virt -kernel */
OUTPUT_ARCH(riscv)
OUTPUT_FORMAT(elf64-littleriscv)
ENTRY(_start)

SECTIONS
{
    . = 0x80200000;

    .text : ALIGN(4096) {
        *(.text.boot .text.boot.*)
        *(.text .text.*)
    }

    .rodata : ALIGN(8) {
        *(.rodata .rodata.*)
    }

    .data : ALIGN(8) {
        *(.data .data.*)
    }

    .bss : ALIGN(16) {
        *(.bss .bss.*)
        *(COMMON)
    }

    /DISCARD/ : {
        *(.eh_frame*)
        *(.note.GNU-stack*)
    }
}
