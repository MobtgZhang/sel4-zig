//! aarch64 主机：占位 .s 符号可链接。
extern fn sel4_zig_fastpath_asm_placeholder() callconv(.c) void;

test "fastpath asm placeholder links (aarch64 host)" {
    sel4_zig_fastpath_asm_placeholder();
}
