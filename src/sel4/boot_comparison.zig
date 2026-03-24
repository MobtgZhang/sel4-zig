//! 阶段二：Multiboot 与 UEFI 关键差异（idea1.md 表格的代码化）。
//! 放在 `src/sel4/` 以便 `migration_tests` 与 UEFI 根模块均可引用。
const std = @import("std");

pub const Row = struct {
    aspect: []const u8,
    multiboot: []const u8,
    uefi: []const u8,
};

pub const table: []const Row = &.{
    .{ .aspect = "内存信息来源", .multiboot = "multiboot_info_t / mbi", .uefi = "GetMemoryMap()" },
    .{ .aspect = "分页状态", .multiboot = "由 bootloader 设置", .uefi = "固件已建立 4KiB 分页" },
    .{ .aspect = "CPU 模式", .multiboot = "保护模式/长模式切换", .uefi = "长模式（应用入口约定）" },
    .{ .aspect = "硬件初始化", .multiboot = "内核需自举更多", .uefi = "Boot Services 提供" },
};

test "boot comparison table (idea1 phase 2)" {
    try std.testing.expectEqual(@as(usize, 4), table.len);
    try std.testing.expectEqualStrings("GetMemoryMap()", table[0].uefi);
}
