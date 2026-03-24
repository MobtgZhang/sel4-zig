//! ideas/idea1.md 六阶段索引：便于 `zig build test` 与 `registry` 统一引用，避免文档与代码脱节。
const std = @import("std");

/// 阶段一：上游 `seL4/` 内与引导/内存最相关的路径（通读用）。
pub const phase1_boot_and_memory_paths = [_][]const u8{
    "src/arch/x86/64/head.S",
    "src/arch/x86/kernel/boot_sys.c",
    "src/arch/x86/kernel/boot.c",
    "src/kernel/boot.c",
};

/// idea1.md 中「关键目录结构」摘要（与阶段一对应）。
pub const phase1_src_tree_note =
    \\seL4/src/: arch/x86|arm(含aarch64的64/)|riscv, kernel/, object/, fastpath/
    \\seL4/include/, libsel4/, tools/
;

/// 阶段三 3.2：迁移优先级标签（与 `migration_priority.zig` 模块路径一致）。
pub const phase3_priority_labels = [_][]const u8{
    "P1 machine/tlb",
    "P2 mmu/boot",
    "P3 untyped/cnode",
    "P4 thread/syscall",
};

pub fn referenceAll() void {
    _ = phase1_boot_and_memory_paths.len;
    _ = phase1_src_tree_note.len;
    _ = phase3_priority_labels.len;
}

test "idea1 phases index" {
    try std.testing.expect(phase1_boot_and_memory_paths.len >= 4);
    try std.testing.expect(phase3_priority_labels.len == 4);
}
