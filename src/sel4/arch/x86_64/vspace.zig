//! 对照 `arch/x86/kernel/vspace.c` + `arch/x86/64/kernel/vspace.c`：页表项与索引常量（尚无完整映射实现）。
const std = @import("std");
pub const upstream_vspace_rel = "arch/x86/kernel/vspace.c";
pub const upstream_vspace_64_rel = "arch/x86/64/kernel/vspace.c";

pub const pte_present: u64 = 1 << 0;
pub const pte_rw: u64 = 1 << 1;
pub const pte_us: u64 = 1 << 2;
pub const pte_pwt: u64 = 1 << 3;
pub const pte_pcd: u64 = 1 << 4;
pub const pte_accessed: u64 = 1 << 5;
pub const pte_dirty: u64 = 1 << 6;
pub const pte_pat: u64 = 1 << 7;
pub const pte_global: u64 = 1 << 8;
pub const pte_nx: u64 = 1 << 63;

pub const page_shift: u6 = 12;
pub const page_size: u64 = 1 << page_shift;

/// 4KiB PTE：低 12 位为属性，物理页框对齐。
pub fn pteFromPhys(phys_aligned: u64, flags: u64) u64 {
    return (phys_aligned & 0x000ffffffffff000) | (flags & 0xfff);
}

/// `level`：0 = PT，1 = PD，2 = PDPT，3 = PML4（与 Intel 页表层级一致）。
pub fn virtPageTableIndex(virt: u64, level: u2) u9 {
    const shift: u6 = 12 + 9 * @as(u6, level);
    return @truncate((virt >> shift) & 0x1ff);
}

test "vspace pte 4k present+rw" {
    const p = pteFromPhys(0x1000, pte_present | pte_rw);
    try std.testing.expect((p & pte_present) != 0);
    try std.testing.expect((p & pte_rw) != 0);
    try std.testing.expectEqual(@as(u64, 0x1000), p & 0x000ffffffffff000);
}

test "vspace virt indices" {
    const v: u64 = @as(u64, 0x100) << 39;
    try std.testing.expectEqual(@as(u9, 0x100), virtPageTableIndex(v, 3));
    try std.testing.expectEqual(@as(u9, 0), virtPageTableIndex(v, 2));
}
