/* Multiboot2 and Xen PVH entry into the x86-64 kernel. */
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

        /* XEN_ELFNOTE_PHYS32_ENTRY: 32-bit entry with paging disabled. */
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
        .skip 131072
stack_top:
        .balign 4096
boot_pml4: .skip 4096
boot_pdpt: .skip 4096
boot_pd: .skip 16384

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
        /* Preserve the PVH start-info pointer and distinguish it from Multiboot. */
        .global pvh_boot32
pvh_boot32:
        cli
        movl    $1, %ebp
        jmp     boot_from_multiboot

        .global _start
_start:
        cli
        /* Multiboot2: EAX = magic */
        cmpl $0x36d76289, %eax
        jne 3f

        xorl    %ebp, %ebp
boot_from_multiboot:
        cld
        movl    $stack_top, %esp
        andl    $~0xF, %esp

        /* Page tables belong to the kernel image, never to firmware scratch RAM. */
        movl    $boot_pml4, %edi
        xorl    %eax, %eax
        movl    $6144, %ecx
        rep stosl
        movl    $boot_pdpt, %eax
        orl     $3, %eax
        movl    %eax, boot_pml4
        xorl    %ecx, %ecx
4:
        movl    %ecx, %eax
        shll    $12, %eax
        addl    $boot_pd, %eax
        orl     $3, %eax
        movl    %eax, boot_pdpt(,%ecx,8)
        incl    %ecx
        cmpl    $4, %ecx
        jne     4b
        /* Identity-map the first 4 GiB with 2 MiB pages. */
        xorl    %ecx, %ecx
5:
        movl    %ecx, %eax
        shll    $21, %eax
        orl     $0x83, %eax
        movl    %eax, boot_pd(,%ecx,8)
        incl    %ecx
        cmpl    $2048, %ecx
        jne     5b
        movl    $boot_pml4, %eax
        movl    %eax, %cr3

        movl    %cr4, %eax
        orl     $((1 << 5) | (1 << 9) | (1 << 10)), %eax
        movl    %eax, %cr4

        movl    $0xC0000080, %ecx
        rdmsr
        orl     $(1 << 8), %eax
        wrmsr

        movl    %cr0, %eax
        andl    $~((1 << 2) | (1 << 3)), %eax
        orl     $((1 << 31) | (1 << 1)), %eax
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
        movabs  $pvh_saved, %rax
        mov     %rbp, (%rax)
        fninit
        xor     %edi, %edi
        call    kmain

2:
        hlt
        jmp     2b

        .code32
3:
        hlt
        jmp     3b
