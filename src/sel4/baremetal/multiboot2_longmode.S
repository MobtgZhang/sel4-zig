/* Multiboot2 → 长模式入口；供 QEMU -kernel 加载。AT&T 语法（LLVM 集成汇编） */
        .section .multiboot_header, "a"
        .align 8
mb2_start:
        .long 0xe85250d6
        .long 0
        .long (mb2_end - mb2_start)
        .long -(0xe85250d6 + 0 + (mb2_end - mb2_start))

        /* entry address tag, type 3 */
        .align 8
        .word 3
        .word 0
        .long 12
        .long _start

        /* end tag */
        .align 8
        .word 0
        .word 0
        .long 8
mb2_end:

        /* QEMU -kernel：XEN_ELFNOTE_PHYS32_ENTRY(18)，32 位无分页入口 */
        .section .note.Xen, "a", @note
        .balign 4
        .long 4
        .long 4
        .long 18
        .ascii "Xen\0"
        .balign 4
        .long pvh_boot32

        .section .bss
        .align 16
        .global stack_top
        .skip 32768
stack_top:

        .section .rodata
        .align 8
gdt64:
        .quad 0
        /* 64-bit code: present, ring0, exec/read, long mode */
        .quad 0x00af9a000000ffff
        /* 64-bit data */
        .quad 0x00cf92000000ffff
gdt64_end:

        .align 4
gdt_ptr:
        .word gdt64_end - gdt64 - 1
        .long gdt64

        .section .text
        .code32
        /* PVH：无 Multiboot 寄存器约定，伪造 magic 后走公共路径 */
        .global pvh_boot32
pvh_boot32:
        cli
        xorl    %ebx, %ebx
        movl    $0x36d76289, %eax
        jmp     boot_from_multiboot

        .global _start
_start:
        cli
        /* Multiboot2: EAX = magic */
        cmpl $0x36d76289, %eax
        jne 3f

boot_from_multiboot:
        movl    $stack_top, %esp
        andl    $~0xF, %esp

        /* 清零页表占位 0x1000–0x3FFF */
        movl    $0x1000, %edi
        xorl    %eax, %eax
        movl    $3072, %ecx
        rep stosl

        /* PML4[0] → PDPT @ 0x2000 */
        movl    $0x2003, 0x1000
        movl    $0, 0x1004
        /* PDPT[0] → PD @ 0x3000 */
        movl    $0x3003, 0x2000
        movl    $0, 0x2004
        /* PD[0]：2MiB 大页，覆盖 0–2MiB（含本内核 @ 1MiB） */
        movl    $0x83, 0x3000
        movl    $0, 0x3004

        movl    $0x1000, %eax
        movl    %eax, %cr3

        movl    %cr4, %eax
        orl     $(1 << 5), %eax
        movl    %eax, %cr4

        movl    $0xC0000080, %ecx
        rdmsr
        orl     $(1 << 8), %eax
        wrmsr

        movl    %cr0, %eax
        orl     $(1 << 31), %eax
        movl    %eax, %cr0

        lgdt    gdt_ptr
        ljmpl   $8, $1f

        .code64
1:
        movw    $16, %ax
        movw    %ax, %ds
        movw    %ax, %es
        movw    %ax, %fs
        movw    %ax, %gs
        movw    %ax, %ss

        movabs  $stack_top, %rsp
        andq    $~0xF, %rsp

        movabs  $mb2_saved, %rax
        mov     %rbx, (%rax)
        xor     %edi, %edi
        call    kmain

2:
        hlt
        jmp     2b

        .code32
3:
        hlt
        jmp     3b
