/* lidt 10 字节描述符：limit(u16)+base(u64)，指针由 RDI 传入（System V AMD64） */
        .section .text
        .global x86_lidt
        .code64
x86_lidt:
        lidt    (%rdi)
        ret
