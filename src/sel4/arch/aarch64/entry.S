/* QEMU virt Linux Image protocol: x0 holds the physical DTB pointer. */
.section .text.boot, "ax"
.global _start
.type _start, %function

_start:
    b       arm_boot
    .long   0
    .quad   0x80000
    .quad   kernel_image_end - _start
    .quad   0
    .quad   0
    .quad   0
    .quad   0
    .long   0x644d5241
    .long   0
arm_boot:
    msr     daifset, #0xf
    mrs     x1, CurrentEL
    cmp     x1, #8
    b.ne    1f
    msr     cptr_el2, xzr
    mov     x1, #(1 << 31)
    msr     hcr_el2, x1
    mov     x1, #3
    msr     cnthctl_el2, x1
    msr     cntvoff_el2, xzr
    adrp    x1, stack_top
    add     x1, x1, :lo12:stack_top
    msr     sp_el1, x1
    adr     x1, 1f
    msr     elr_el2, x1
    mov     x1, #0x3c5
    msr     spsr_el2, x1
    eret
1:
    mov     x1, #(3 << 20)
    msr     cpacr_el1, x1
    isb
    mov     x19, x0
    adrp    x1, stack_top
    add     x1, x1, :lo12:stack_top
    mov     sp, x1
    mov     x0, x19
    bl      kmain
0:  wfe
    b       0b

.section .bss.stack, "aw", @nobits
.align 16
.space 262144
stack_top:

.section .text.boot.uefi, "ax"
.global uefi_entry
.type uefi_entry, %function
uefi_entry:
    msr daifset, #0xf
    dsb sy
    mrs x1, sctlr_el1
    bic x1, x1, #1
    bic x1, x1, #4
    bic x1, x1, #4096
    msr sctlr_el1, x1
    isb
    tlbi vmalle1
    dsb sy
    isb
    mov x1, #(3 << 20)
    msr cpacr_el1, x1
    isb
    adrp x1, stack_top
    add x1, x1, :lo12:stack_top
    mov sp, x1
    bl uefi_kmain
    b .
