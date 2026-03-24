/* QEMU virt：x0 = 设备树物理指针 */
.section .text.boot, "ax"
.global _start
.type _start, %function

_start:
    mov     x19, x0
    adr     x1, stack_top
    mov     sp, x1
    mov     x0, x19
    bl      kmain
0:  wfe
    b       0b

.section .bss.stack, "aw", @nobits
.align 16
.space 65536
stack_top:
