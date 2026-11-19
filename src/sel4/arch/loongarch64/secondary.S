/* Firmware mailbox entry is physical; establish supervisor direct windows. */
.text
.global secondary_entry
secondary_entry:
    li.d $t0, 0x8000000000000001
    csrwr $t0, 0x180
    li.d $t0, 0x9000000000000011
    csrwr $t0, 0x181
    li.w $t0, 1
    csrwr $t0, 0x2
    la.local $t0, secondary_mapped
    li.d $t1, 0x9000000000000000
    or $t0, $t0, $t1
    li.w $t2, 0x11
    csrwr $t2, 0x182
    li.w $t2, 0xb0
    csrwr $t2, 0x0
    jirl $zero, $t0, 0
secondary_mapped:
    csrwr $zero, 0x182
    li.w $t0, 0x100c
    li.w $t1, -1
    iocsrwr.w $t1, $t0
    la.local $t0, secondary_boot_index
    ld.d $a0, $t0, 0
    la.local $t0, secondary_boot_stacks
    slli.d $t1, $a0, 3
    add.d $t0, $t0, $t1
    ld.d $sp, $t0, 0
    bl secondary_main
1:  idle 0
    b 1b
