/* 由 UEFI 加载的 Zig 内核：无 Multiboot/PVH，入口 kmain */
OUTPUT_FORMAT(elf64-x86-64)
OUTPUT_ARCH(i386:x86-64)
ENTRY(kmain)

/* 避开 0x100000（Multiboot 内核）及固件低区；QEMU+OVMF 下 16MiB 处常可 AllocateAddress */
SECTIONS
{
    . = 0x1000000;

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
