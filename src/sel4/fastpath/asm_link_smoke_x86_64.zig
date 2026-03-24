//! 仅在 **主机为 x86_64** 时由 `migration_tests.zig` comptime 引入（见该文件顶部），配合 `placeholder_x86_64.s`。
extern fn sel4_zig_fastpath_asm_placeholder() callconv(.c) void;

test "phase3 fastpath asm placeholder linked" {
    sel4_zig_fastpath_asm_placeholder();
}
