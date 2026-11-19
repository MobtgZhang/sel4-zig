/* Per-CPU ring transition. Frame order is checked against user_runtime.zig. */
.section .text
.code64
.global x86_load_user_gdt
x86_load_user_gdt:
    lgdt (%rdi)
    pushq $8
    leaq 1f(%rip), %rax
    pushq %rax
    lretq
1:
    movw $16, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %ss
    movw $40, %ax
    ltr %ax
    ret

.global x86_timer_trap
x86_timer_trap:
    swapgs
    cld
    pushq %rax
    pushq %rbx
    pushq %rcx
    pushq %rdx
    pushq %rsi
    pushq %rdi
    pushq %rbp
    pushq %r8
    pushq %r9
    pushq %r10
    pushq %r11
    pushq %r12
    pushq %r13
    pushq %r14
    pushq %r15
    movq %gs:16, %rax
    fxsave64 (%rax)
    movq %rsp, %rdi
    call terminal_timer_dispatch
    movq %rax, %rdi
    jmp x86_restore_user
.global x86_local_timer_trap
x86_local_timer_trap:
    jmp x86_timer_trap
.global x86_spurious_trap
x86_spurious_trap:
    iretq
.global x86_terminal_trap
x86_terminal_trap:
    swapgs
    cld
    pushq %rax
    pushq %rbx
    pushq %rcx
    pushq %rdx
    pushq %rsi
    pushq %rdi
    pushq %rbp
    pushq %r8
    pushq %r9
    pushq %r10
    pushq %r11
    pushq %r12
    pushq %r13
    pushq %r14
    pushq %r15
    movq %gs:16, %rax
    fxsave64 (%rax)
    movq %rsp, %rdi
    call terminal_dispatch
    movq %rax, %rdi
.global x86_restore_user
x86_restore_user:
    movq %gs:16, %rax
    fxrstor64 (%rax)
    movq %rdi, %rsp
    popq %r15
    popq %r14
    popq %r13
    popq %r12
    popq %r11
    popq %r10
    popq %r9
    popq %r8
    popq %rbp
    popq %rdi
    popq %rsi
    popq %rdx
    popq %rcx
    popq %rbx
    popq %rax
    swapgs
    iretq

.macro user_exception name, number, error_code
.global \name
\name:
.if !\error_code
    pushq $0
.endif
    pushq $\number
    jmp x86_exception_common
.endm
user_exception x86_user_de, 0, 0
user_exception x86_user_ud, 6, 0
user_exception x86_user_gp, 13, 1
user_exception x86_user_pf, 14, 1
x86_exception_common:
    testb $3, 24(%rsp)
    jz 1f
    swapgs
1:  cld
    pushq %rax
    pushq %rbx
    pushq %rcx
    pushq %rdx
    pushq %rsi
    pushq %rdi
    pushq %rbp
    pushq %r8
    pushq %r9
    pushq %r10
    pushq %r11
    pushq %r12
    pushq %r13
    pushq %r14
    pushq %r15
    movq %gs:16, %rax
    fxsave64 (%rax)
    movq %rsp, %rdi
    call terminal_exception_dispatch
    movq %rax, %rdi
    jmp x86_restore_user

.global x86_ipi_trap
x86_ipi_trap:
    swapgs
    cld
    pushq %rax
    pushq %rbx
    pushq %rcx
    pushq %rdx
    pushq %rsi
    pushq %rdi
    pushq %rbp
    pushq %r8
    pushq %r9
    pushq %r10
    pushq %r11
    pushq %r12
    pushq %r13
    pushq %r14
    pushq %r15
    movq %gs:16, %rax
    fxsave64 (%rax)
    movq %rsp, %rdi
    call terminal_ipi_dispatch
    movq %rax, %rdi
    jmp x86_restore_user

.global x86_device_33
x86_device_33:
    pushq $0
    pushq $33
    jmp x86_device_common

.global x86_device_34
x86_device_34:
    pushq $0
    pushq $34
    jmp x86_device_common

.global x86_device_35
x86_device_35:
    pushq $0
    pushq $35
    jmp x86_device_common

.global x86_device_36
x86_device_36:
    pushq $0
    pushq $36
    jmp x86_device_common

.global x86_device_37
x86_device_37:
    pushq $0
    pushq $37
    jmp x86_device_common

.global x86_device_38
x86_device_38:
    pushq $0
    pushq $38
    jmp x86_device_common

.global x86_device_39
x86_device_39:
    pushq $0
    pushq $39
    jmp x86_device_common

.global x86_device_40
x86_device_40:
    pushq $0
    pushq $40
    jmp x86_device_common

.global x86_device_41
x86_device_41:
    pushq $0
    pushq $41
    jmp x86_device_common

.global x86_device_42
x86_device_42:
    pushq $0
    pushq $42
    jmp x86_device_common

.global x86_device_43
x86_device_43:
    pushq $0
    pushq $43
    jmp x86_device_common

.global x86_device_44
x86_device_44:
    pushq $0
    pushq $44
    jmp x86_device_common

.global x86_device_45
x86_device_45:
    pushq $0
    pushq $45
    jmp x86_device_common

.global x86_device_46
x86_device_46:
    pushq $0
    pushq $46
    jmp x86_device_common

.global x86_device_47
x86_device_47:
    pushq $0
    pushq $47
    jmp x86_device_common

x86_device_common:
    testb $3, 24(%rsp)
    jz 1f
    swapgs
1:  cld
    pushq %rax
    pushq %rbx
    pushq %rcx
    pushq %rdx
    pushq %rsi
    pushq %rdi
    pushq %rbp
    pushq %r8
    pushq %r9
    pushq %r10
    pushq %r11
    pushq %r12
    pushq %r13
    pushq %r14
    pushq %r15
    movq %gs:16, %rax
    fxsave64 (%rax)
    movq %rsp, %rdi
    call terminal_device_dispatch
    movq %rax, %rdi
    jmp x86_restore_user

.section .rodata
.balign 8
.global x86_device_vectors
x86_device_vectors:
    .long x86_device_33 - x86_device_vectors
    .long x86_device_34 - x86_device_vectors
    .long x86_device_35 - x86_device_vectors
    .long x86_device_36 - x86_device_vectors
    .long x86_device_37 - x86_device_vectors
    .long x86_device_38 - x86_device_vectors
    .long x86_device_39 - x86_device_vectors
    .long x86_device_40 - x86_device_vectors
    .long x86_device_41 - x86_device_vectors
    .long x86_device_42 - x86_device_vectors
    .long x86_device_43 - x86_device_vectors
    .long x86_device_44 - x86_device_vectors
    .long x86_device_45 - x86_device_vectors
    .long x86_device_46 - x86_device_vectors
    .long x86_device_47 - x86_device_vectors

.section .text
.global x86_native_syscall
x86_native_syscall:
    swapgs
    movq %rsp, %gs:8
    movq %gs:0, %rsp
    pushq $0x1b
    pushq %gs:8
    pushq %r11
    pushq $0x23
    pushq %rcx
    cld
    pushq %rax
    pushq %rbx
    pushq %rcx
    pushq %rdx
    pushq %rsi
    pushq %rdi
    pushq %rbp
    pushq %r8
    pushq %r9
    pushq %r10
    pushq %r11
    pushq %r12
    pushq %r13
    pushq %r14
    pushq %r15
    movq %gs:16, %rax
    fxsave64 (%rax)
    movq %rsp, %rdi
    call terminal_native_dispatch
    movq %rax, %rdi
    jmp x86_restore_user
