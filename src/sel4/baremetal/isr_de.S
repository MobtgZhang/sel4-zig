/* x86_64 #DE 处理：由 Zig 导出 onDivideError */
        .section .text
        .code64
        .global isr_divide_error
        .align 16
isr_divide_error:
        cli
        pushq   %rbp
        movq    %rsp, %rbp
        andq    $-16, %rsp
        call    onDivideError
0:
        hlt
        jmp     0b
