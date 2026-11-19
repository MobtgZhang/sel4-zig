/* Firmware callbacks run on a private, page-owned stack. */
.text
.global firmware_stack_call
firmware_stack_call:
    stp x19, x30, [sp, #-16]!
    mov x19, sp
    mov sp, x0
    bl firmware_boot_body
    mov sp, x19
    ldp x19, x30, [sp], #16
    ret
