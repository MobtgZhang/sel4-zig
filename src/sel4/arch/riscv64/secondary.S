/* SBI HSM enters in S-mode: a0 = hart ID, a1 = opaque logical index. */
.text
.global secondary_entry
secondary_entry:
    csrci sstatus, 2
    csrw satp, zero
    sfence.vma
    li t0, 0x6000
    csrs sstatus, t0
    mv tp, a0
    la t0, secondary_boot_stacks
    slli t1, a1, 3
    add t0, t0, t1
    ld sp, 0(t0)
    mv a0, a1
    call secondary_main
1:  wfi
    j 1b
