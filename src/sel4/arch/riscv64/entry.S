/* QEMU virt：a0 = hartid，a1 = 设备树物理指针 */
.section .text.boot, "ax"
.global _start
.type _start, @function

_start:
    mv      s0, a1
    la      sp, stack_top
    mv      a0, s0
    call    kmain
0:  wfi
    j       0b

.section .bss.stack, "aw", @nobits
.align 16
.space 65536
stack_top:
