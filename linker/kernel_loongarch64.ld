/* LoongArch 64 裸 ELF：QEMU virt 常见 DRAM 起始（无官方 seL4 上游；占位） */
OUTPUT_ARCH(loongarch64)
OUTPUT_FORMAT(elf64-loongarch)
ENTRY(_start)

SECTIONS
{
    . = 0x9000000010000000;

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
