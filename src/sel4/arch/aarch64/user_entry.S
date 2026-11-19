.section .text, "ax"
.balign 2048
.global arch_user_vector
arch_user_vector:
    b arch_arm_sync
.balign 128
    b arch_arm_irq
.balign 128
    b arch_arm_sync
.balign 128
    b arch_arm_sync
.balign 128
    b arch_arm_sync
.balign 128
    b arch_arm_irq
.balign 128
    b arch_arm_sync
.balign 128
    b arch_arm_sync
.balign 128
    b arch_arm_sync
.balign 128
    b arch_arm_irq
.balign 128
    b arch_arm_sync
.balign 128
    b arch_arm_sync
.balign 128
    b arch_arm_sync
.balign 128
    b arch_arm_irq
.balign 128
    b arch_arm_sync
.balign 128
    b arch_arm_sync
.balign 128
.macro arm_entry name, kind
\name:
    sub sp, sp, #800
    stp x0, x1, [sp, #0]
    stp x2, x3, [sp, #16]
    stp x4, x5, [sp, #32]
    stp x6, x7, [sp, #48]
    stp x8, x9, [sp, #64]
    stp x10, x11, [sp, #80]
    stp x12, x13, [sp, #96]
    stp x14, x15, [sp, #112]
    stp x16, x17, [sp, #128]
    stp x18, x19, [sp, #144]
    stp x20, x21, [sp, #160]
    stp x22, x23, [sp, #176]
    stp x24, x25, [sp, #192]
    stp x26, x27, [sp, #208]
    stp x28, x29, [sp, #224]
    str x30, [sp, #240]
    mrs x0, sp_el0
    str x0, [sp, #248]
    mrs x0, elr_el1
    str x0, [sp, #256]
    mrs x0, spsr_el1
    str x0, [sp, #264]
    stp q0, q1, [sp, #272]
    stp q2, q3, [sp, #304]
    stp q4, q5, [sp, #336]
    stp q6, q7, [sp, #368]
    stp q8, q9, [sp, #400]
    stp q10, q11, [sp, #432]
    stp q12, q13, [sp, #464]
    stp q14, q15, [sp, #496]
    stp q16, q17, [sp, #528]
    stp q18, q19, [sp, #560]
    stp q20, q21, [sp, #592]
    stp q22, q23, [sp, #624]
    stp q24, q25, [sp, #656]
    stp q26, q27, [sp, #688]
    stp q28, q29, [sp, #720]
    stp q30, q31, [sp, #752]
    mrs x0, fpcr
    str x0, [sp, #784]
    mrs x0, fpsr
    str x0, [sp, #792]
    mov x0, sp
    mov x1, #\kind
    bl terminal_arch_dispatch
    add sp, sp, #800
    b arch_user_restore
.endm
arm_entry arch_arm_sync, 0
arm_entry arch_arm_irq, 1
.global arch_user_restore
arch_user_restore:
    mov x30, x0
    ldr x0, [x30, #248]
    msr sp_el0, x0
    ldr x0, [x30, #256]
    msr elr_el1, x0
    ldr x0, [x30, #264]
    msr spsr_el1, x0
    ldr x0, [x30, #784]
    msr fpcr, x0
    ldr x0, [x30, #792]
    msr fpsr, x0
    ldp q0, q1, [x30, #272]
    ldp q2, q3, [x30, #304]
    ldp q4, q5, [x30, #336]
    ldp q6, q7, [x30, #368]
    ldp q8, q9, [x30, #400]
    ldp q10, q11, [x30, #432]
    ldp q12, q13, [x30, #464]
    ldp q14, q15, [x30, #496]
    ldp q16, q17, [x30, #528]
    ldp q18, q19, [x30, #560]
    ldp q20, q21, [x30, #592]
    ldp q22, q23, [x30, #624]
    ldp q24, q25, [x30, #656]
    ldp q26, q27, [x30, #688]
    ldp q28, q29, [x30, #720]
    ldp q30, q31, [x30, #752]
    ldp x0, x1, [x30, #0]
    ldp x2, x3, [x30, #16]
    ldp x4, x5, [x30, #32]
    ldp x6, x7, [x30, #48]
    ldp x8, x9, [x30, #64]
    ldp x10, x11, [x30, #80]
    ldp x12, x13, [x30, #96]
    ldp x14, x15, [x30, #112]
    ldp x16, x17, [x30, #128]
    ldp x18, x19, [x30, #144]
    ldp x20, x21, [x30, #160]
    ldp x22, x23, [x30, #176]
    ldp x24, x25, [x30, #192]
    ldp x26, x27, [x30, #208]
    ldp x28, x29, [x30, #224]
    ldr x30, [x30, #240]
    eret
