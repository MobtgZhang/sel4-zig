/* QEMU LoongArch virt：a0=hartid，a1=DTB（与 OpenSBI/Linux 引导约定类似；占位） */
.section .text.boot, "ax"
.global _start
.type _start, @function

_start:
    move    $t0, $a1
    la.local $sp, stack_top
    move    $a0, $t0
    bl      kmain
0:  idle    0
    b       0b

.section .bss.stack, "aw", @nobits
.align 16
.space 65536
stack_top:
