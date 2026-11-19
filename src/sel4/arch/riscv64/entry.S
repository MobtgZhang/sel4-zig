/* OpenSBI supervisor entry: a0 is the hart ID and a1 is the DTB pointer. */
.section .text.boot, "ax"
.global _start
.type _start, @function

_start:
    csrci   sstatus, 2
    li      t0, 0x6000
    csrs    sstatus, t0
    mv      tp, a0
    mv      s0, a1
    la      t0, boot_hardware_id
    sd      a0, 0(t0)
    la      sp, stack_top
    mv      a0, s0
    call    kmain
0:  wfi
    j       0b

.section .bss.stack, "aw", @nobits
.align 16
.space 262144
stack_top:

.section .text.boot.uefi, "ax"
.global uefi_entry
.type uefi_entry, @function
uefi_entry:
    csrci sstatus, 2
    mv tp, a1
    la t0, boot_hardware_id
    sd a1, 0(t0)
    csrw satp, zero
    sfence.vma
    li t0, 0x6000
    csrs sstatus, t0
    la sp, stack_top
    call uefi_kmain
    j .
