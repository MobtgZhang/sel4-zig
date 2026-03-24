/* 主机为 aarch64 时 migration_tests 链接占位（快路径接线位）。 */
.text
.global sel4_zig_fastpath_asm_placeholder
.type sel4_zig_fastpath_asm_placeholder, %function
sel4_zig_fastpath_asm_placeholder:
    ret
