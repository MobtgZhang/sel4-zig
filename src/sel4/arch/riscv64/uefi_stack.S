/* Firmware callbacks run on a private, page-owned stack. */
.text
.global firmware_stack_call
firmware_stack_call:
    addi sp, sp, -16
    sd s0, 0(sp)
    sd ra, 8(sp)
    mv s0, sp
    mv sp, a0
    call firmware_boot_body
    mv sp, s0
    ld s0, 0(sp)
    ld ra, 8(sp)
    addi sp, sp, 16
    ret
