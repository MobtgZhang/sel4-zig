/* Copy this relocation-free blob to physical 0x8000 before sending SIPI vector 8. */
.section .rodata.ap_trampoline, "a"
.balign 16
.global ap_trampoline_start
.global ap_trampoline_end
.code16
ap_trampoline_start:
    cli
    cld
    xorw %ax, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %ss
    lgdtl 0x8000 + (ap_gdt_ptr - ap_trampoline_start)
    movl %cr0, %eax
    orl $1, %eax
    movl %eax, %cr0
    .byte 0x66, 0xea
    .long 0x8000 + (ap_protected - ap_trampoline_start)
    .word 8
.code32
ap_protected:
    movw $16, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %ss
    movl %cr4, %eax
    orl $0x620, %eax
    movl %eax, %cr4
    movl 0x8e00, %eax
    movl %eax, %cr3
    movl $0xc0000080, %ecx
    rdmsr
    orl $0x900, %eax
    wrmsr
    movl %cr0, %eax
    andl $~12, %eax
    orl $0x80000002, %eax
    movl %eax, %cr0
    .byte 0xea
    .long 0x8000 + (ap_long - ap_trampoline_start)
    .word 24
.code64
ap_long:
    movq 0x8e08, %rsp
    andq $-16, %rsp
    movq 0x8e18, %rdi
    movq 0x8e10, %rax
    fninit
    call *%rax
1:  cli
    hlt
    jmp 1b
.balign 8
ap_gdt:
    .quad 0
    .quad 0x00cf9a000000ffff
    .quad 0x00cf92000000ffff
    .quad 0x00af9a000000ffff
ap_gdt_ptr:
    .word 31
    .long 0x8000 + (ap_gdt - ap_trampoline_start)
ap_trampoline_end:
.section .note.GNU-stack, "", @progbits
