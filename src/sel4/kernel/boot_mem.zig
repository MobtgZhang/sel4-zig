//! 对照 `seL4/src/kernel/boot.c` 中 `merge_regions` / `reserve_region` 的**最小可测**子集（无 printf、无全局 `ndks_boot`）。
const std = @import("std");

pub const PRegion = struct {
    start: u64,
    end: u64,

    pub fn isEmpty(r: PRegion) bool {
        return r.start >= r.end;
    }
};

/// 与 `boot/handoff.zig` 中 `HandoffPhysRegion` 布局一致，便于从 `BootHandoff` 切片传入。
pub const HandoffPhysRegion = extern struct {
    start: u64,
    end: u64,
};

pub const max_reserved: usize = 16;

/// 与上游 `merge_regions` 等价：将排序后相邻区间合并。
pub fn mergeRegions(regions: []PRegion, count: *usize) void {
    var i: usize = 1;
    while (i < count.*) {
        if (regions[i - 1].end == regions[i].start) {
            regions[i - 1].end = regions[i].end;
            std.mem.copyForwards(PRegion, regions[i .. count.* - 1], regions[i + 1 .. count.*]);
            count.* -= 1;
        } else {
            i += 1;
        }
    }
}

/// 简化版 `reserve_region`：保持按起点有序插入；成功合并时调用 `mergeRegions`。
pub fn reserveRegion(regions: []PRegion, count: *usize, reg: PRegion) bool {
    if (reg.isEmpty()) return true;
    if (count.* >= regions.len) return false;

    var i: usize = 0;
    while (i < count.*) : (i += 1) {
        if (regions[i].start == reg.end) {
            regions[i].start = reg.start;
            mergeRegions(regions, count);
            return true;
        }
        if (regions[i].end == reg.start) {
            regions[i].end = reg.end;
            mergeRegions(regions, count);
            return true;
        }
        if (regions[i].start > reg.end) {
            if (count.* >= regions.len) return false;
            var j: usize = count.*;
            while (j > i) : (j -= 1) {
                regions[j] = regions[j - 1];
            }
            regions[i] = reg;
            count.* += 1;
            mergeRegions(regions, count);
            return true;
        }
    }

    regions[count.*] = reg;
    count.* += 1;
    mergeRegions(regions, count);
    return true;
}

/// 将 `BootHandoff` 中的可用区拷贝为「保留表」演练数据（语义上对应引导期对固件区等的记录，此处仅验证合并算法）。
pub fn seedReservedFromHandoffRegions(
    out: []PRegion,
    count: *usize,
    regions: []const HandoffPhysRegion,
) bool {
    count.* = 0;
    for (regions) |r| {
        if (r.start >= r.end) continue;
        if (!reserveRegion(out, count, .{ .start = r.start, .end = r.end })) return false;
    }
    return true;
}

test "boot_mem merge adjacent" {
    var buf: [max_reserved]PRegion = undefined;
    var n: usize = 0;
    try std.testing.expect(reserveRegion(&buf, &n, .{ .start = 0x1000, .end = 0x2000 }));
    try std.testing.expect(reserveRegion(&buf, &n, .{ .start = 0x2000, .end = 0x3000 }));
    try std.testing.expectEqual(@as(usize, 1), n);
    try std.testing.expectEqual(@as(u64, 0x1000), buf[0].start);
    try std.testing.expectEqual(@as(u64, 0x3000), buf[0].end);
}
