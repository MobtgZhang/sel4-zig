/* x86_64 #PF：错误码在栈顶，经 rdi/rsi 传入 Zig */
        .section .text
        .code64
        .global isr_page_fault
        .align 16
isr_page_fault:
        cli
        pushq   %rbp
        movq    %rsp, %rbp
        movq    8(%rbp), %rdi
        movq    %cr2, %rsi
        andq    $-16, %rsp
        call    onPageFaultRegs
0:
        hlt
        jmp     0b
