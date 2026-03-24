/* x86_64 裸机内核：Multiboot2 加载地址 1MiB（与 QEMU -kernel 一致） */
OUTPUT_FORMAT(elf64-x86-64)
OUTPUT_ARCH(i386:x86-64)
ENTRY(_start)

SECTIONS
{
    . = 0x100000;

    .multiboot_header : ALIGN(8) {
        KEEP(*(.multiboot_header))
    }

    .note.Xen : ALIGN(4) {
        KEEP(*(.note.Xen))
    }

    .text : ALIGN(8) {
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
