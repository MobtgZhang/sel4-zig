/* QEMU direct ELF boot. CPU starts in direct-address mode at PLV0.
 * DMW0 is uncached, DMW1 cached; a2 carries the synthetic EFI system table.
 */
.section .text.boot, "ax"
.global _start
.type _start, @function

_start:
    li.d    $t0, 0x8000000000000001
    csrwr   $t0, 0x180
    li.d    $t0, 0x9000000000000011
    csrwr   $t0, 0x181
    la.local $t0, loong_mapped
    li.d    $t1, 0x9000000000000000
    or      $t0, $t0, $t1
    jirl    $zero, $t0, 0
loong_mapped:
    li.w    $t0, 0xb0
    csrwr   $t0, 0x0
    /* Enable scalar floating-point registers used by the Zig ABI. */
    li.w    $t0, 1
    csrwr   $t0, 0x2
    move    $s0, $a2
    la.local $sp, stack_top
    move    $a0, $s0
    bl      kmain
0:  idle    0
    b       0b

.section .bss.stack, "aw", @nobits
.align 16
/* Boot validation and the allocation-free core tests use nested stack objects.
 * Match the other non-x86 boot stacks; this stack is reserved with the kernel.
 */
.space 262144
stack_top:

.section .text.boot.uefi, "ax"
.global uefi_entry
.type uefi_entry, @function
uefi_entry:
    move $s0, $a0
    li.d $t0, 0x8000000000000001
    csrwr $t0, 0x180
    li.d $t0, 0x9000000000000011
    csrwr $t0, 0x181
    li.w $t0, 1
    csrwr $t0, 0x2
    la.local $t0, loong_uefi_mapped
    li.d $t1, 0x9000000000000000
    or $t0, $t0, $t1
    li.w $t2, 0x11
    csrwr $t2, 0x182
    li.w $t2, 0xb0
    csrwr $t2, 0x0
    jirl $zero, $t0, 0
loong_uefi_mapped:
    csrwr $zero, 0x182
    la.local $sp, stack_top
    move $a0, $s0
    bl uefi_kmain
    b .
