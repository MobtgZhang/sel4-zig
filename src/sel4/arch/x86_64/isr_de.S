/* x86-64 divide exception: call the Zig onDivideError export. */
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
