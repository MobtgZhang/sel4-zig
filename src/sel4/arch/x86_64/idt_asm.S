/* Load a 10-byte IDT descriptor supplied in RDI (System V AMD64). */
        .section .text
        .global x86_lidt
        .code64
x86_lidt:
        lidt    (%rdi)
        ret
