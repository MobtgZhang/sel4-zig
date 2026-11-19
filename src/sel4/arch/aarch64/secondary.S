/* PSCI enters at EL1 with translation disabled and the logical index in x0. */
.text
.global secondary_entry
secondary_entry:
    msr daifset, #0xf
    mov x1, #(3 << 20)
    msr cpacr_el1, x1
    isb
    adrp x1, secondary_boot_stacks
    add x1, x1, :lo12:secondary_boot_stacks
    ldr x1, [x1, x0, lsl #3]
    mov sp, x1
    bl secondary_main
1:  wfe
    b 1b
