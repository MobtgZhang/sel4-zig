//! 阶段四 4.2：物理内存区域（UEFI 路径替代 Multiboot mmap 解析的第一版）。
//! idea1.md 使用 `usize`；此处用 `u64` 表示物理地址，在 x86_64 等与指针同宽的平台上与 `usize` 模型一致。
const std = @import("std");
const uefi = std.os.uefi;

pub const PhysRegion = struct {
    /// 物理起始地址（含）
    start: u64,
    /// 物理结束地址（不含）
    end: u64,

    pub fn isEmpty(self: PhysRegion) bool {
        return self.start >= self.end;
    }

    pub fn pageCount4k(self: PhysRegion) u64 {
        if (self.isEmpty()) return 0;
        return (self.end - self.start) / 4096;
    }
};

/// 从 UEFI 内存映射迭代器中收集 **conventional_memory** 区间写入 `out`，返回写入条数。
pub fn fromUefiMemoryMapSlice(out: []PhysRegion, slice: uefi.tables.MemoryMapSlice) usize {
    var n: usize = 0;
    var it = slice.iterator();
    while (it.next()) |desc| {
        if (desc.type != .conventional_memory) continue;
        if (n >= out.len) break;
        const start = desc.physical_start;
        const end = start + desc.number_of_pages * 4096;
        out[n] = .{ .start = start, .end = end };
        n += 1;
    }
    return n;
}

/// 阶段四 4.2：从 **紧密排列** 的 `MemoryDescriptor` 切片提取 conventional 区域（对应 idea1.md `fromUefiMemoryMap`）。
/// 若固件 `descriptor_size > @sizeOf(MemoryDescriptor)`，请使用 `fromUefiMemoryMapSlice`。
pub fn fromUefiMemoryMap(out: []PhysRegion, map: []const uefi.tables.MemoryDescriptor) usize {
    var n: usize = 0;
    for (map) |desc| {
        if (desc.type != .conventional_memory) continue;
        if (n >= out.len) break;
        const start = desc.physical_start;
        const end = start + desc.number_of_pages * 4096;
        out[n] = .{ .start = start, .end = end };
        n += 1;
    }
    return n;
}

test "phys region pages" {
    const r = PhysRegion{ .start = 0, .end = 4096 };
    try std.testing.expectEqual(@as(u64, 1), r.pageCount4k());
}

test "fromUefiMemoryMap tight slice" {
    const Mem = uefi.tables.MemoryType;
    const MD = uefi.tables.MemoryDescriptor;
    var d0: MD = std.mem.zeroes(MD);
    d0.type = Mem.loader_code;
    d0.physical_start = 0;
    d0.number_of_pages = 1;
    var d1: MD = std.mem.zeroes(MD);
    d1.type = Mem.conventional_memory;
    d1.physical_start = 0x1000;
    d1.number_of_pages = 2;
    const map = [_]MD{ d0, d1 };
    var out: [4]PhysRegion = undefined;
    const n = fromUefiMemoryMap(&out, &map);
    try std.testing.expectEqual(@as(usize, 1), n);
    try std.testing.expectEqual(@as(u64, 0x1000), out[0].start);
    try std.testing.expectEqual(@as(u64, 0x1000 + 2 * 4096), out[0].end);
}
