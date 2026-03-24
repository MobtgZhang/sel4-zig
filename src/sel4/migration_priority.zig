//! 阶段三 3.2：由底层到高层的迁移顺序（模块根为 `src/sel4/`；上游 `.c` 在并列 `seL4/src/`）。
const std = @import("std");

pub const Entry = struct {
    /// 官方 `src/` 下对照路径线索
    note: []const u8,
    /// 本仓库 Zig 模块（`@import` 路径相对于 `src/sel4/`）
    zig_module: []const u8,
};

/// 由底层到高层；IPC 入口在上游为 `api/syscall.c`（无 `kernel/ipc.c`）。
pub const ordered: []const Entry = &.{
    .{ .note = "arch/x86/64/machine*.c → machine.zig", .zig_module = "arch/x86_64/machine.zig" },
    .{ .note = "arch/x86/64/tlb.c → tlb.zig", .zig_module = "arch/x86_64/tlb.zig" },
    .{ .note = "arch/x86/kernel/vspace.c + arch/x86/64/kernel/vspace.c → vspace.zig / mmu.zig", .zig_module = "arch/x86_64/vspace.zig" },
    .{ .note = "arch/x86/64/mmu.c → mmu.zig", .zig_module = "arch/x86_64/mmu.zig" },
    .{ .note = "arch/x86/kernel/boot_sys.c + arch/x86/kernel/boot.c → boot.zig", .zig_module = "kernel/boot.zig" },
    .{ .note = "kernel/boot.c → boot_mem.zig (merge_regions / reserve_region)", .zig_module = "kernel/boot_mem.zig" },
    .{ .note = "object/untyped.c → untyped.zig", .zig_module = "object/untyped.zig" },
    .{ .note = "object/cnode.c → cnode.zig", .zig_module = "object/cnode.zig" },
    .{ .note = "kernel/thread.c → thread.zig", .zig_module = "kernel/thread.zig" },
    .{ .note = "api/syscall.c → api/syscall.zig + kernel/ipc_dispatch.zig", .zig_module = "api/syscall.zig" },
    .{ .note = "fastpath/fastpath.c → fastpath/fastpath.zig", .zig_module = "fastpath/fastpath.zig" },
    .{ .note = "plat/pc99/machine/*.c → plat/pc99.zig", .zig_module = "plat/pc99.zig" },
    .{ .note = "arch/x86/idle.c → idle/idle.zig", .zig_module = "idle/idle.zig" },
    .{ .note = "arch/arm/64/machine → arch/aarch64/machine.zig", .zig_module = "arch/aarch64/machine.zig" },
    .{ .note = "arch/arm/64/kernel/vspace.c → arch/aarch64/vspace.zig", .zig_module = "arch/aarch64/vspace.zig" },
    .{ .note = "arch/riscv/machine → arch/riscv64/machine.zig", .zig_module = "arch/riscv64/machine.zig" },
    .{ .note = "arch/riscv/kernel/vspace.c → arch/riscv64/vspace.zig", .zig_module = "arch/riscv64/vspace.zig" },
    .{ .note = "LoongArch 实验 → arch/loongarch64/machine.zig", .zig_module = "arch/loongarch64/machine.zig" },
};

test "migration priority order" {
    try std.testing.expect(ordered.len >= 8);
    try std.testing.expectEqualStrings("arch/x86_64/machine.zig", ordered[0].zig_module);
    try std.testing.expectEqualStrings("api/syscall.zig", ordered[9].zig_module);
}
