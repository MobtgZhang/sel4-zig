/* Firmware callbacks run on a private, page-owned stack. */
.text
.global firmware_stack_call
firmware_stack_call:
    addi.d $sp, $sp, -16
    st.d $s0, $sp, 0
    st.d $ra, $sp, 8
    move $s0, $sp
    move $sp, $a0
    bl firmware_boot_body
    move $sp, $s0
    ld.d $s0, $sp, 0
    ld.d $ra, $sp, 8
    addi.d $sp, $sp, 16
    jr $ra
