//! Physical memory ranges extracted from UEFI conventional-memory descriptors.
//! Addresses use explicit 64-bit integers across supported targets.
const std = @import("std");
const uefi = std.os.uefi;

pub const PhysRegion = struct {
    /// Inclusive physical start address.
    start: u64,
    /// Exclusive physical end address.
    end: u64,

    pub fn isEmpty(self: PhysRegion) bool {
        return self.start >= self.end;
    }

    pub fn pageCount4k(self: PhysRegion) u64 {
        if (self.isEmpty()) return 0;
        return (self.end - self.start) / 4096;
    }
};

/// Collect conventional-memory regions from firmware-strided descriptors.
pub fn fromUefiMemoryMapSlice(out: []PhysRegion, slice: uefi.tables.MemoryMapSlice) error{ InvalidMemoryMap, TooManyRegions }!usize {
    var n: usize = 0;
    var it = slice.iterator();
    while (it.next()) |desc| {
        if (desc.type != .conventional_memory) continue;
        if (n >= out.len) return error.TooManyRegions;
        const start = desc.physical_start;
        const size = std.math.mul(u64, desc.number_of_pages, 4096) catch return error.InvalidMemoryMap;
        const end = std.math.add(u64, start, size) catch return error.InvalidMemoryMap;
        if (size == 0) continue;
        out[n] = .{ .start = start, .end = end };
        n += 1;
    }
    return n;
}

/// Collect regions from a tightly packed descriptor array.
/// Use fromUefiMemoryMapSlice when the firmware descriptor stride is larger.
pub fn fromUefiMemoryMap(out: []PhysRegion, map: []const uefi.tables.MemoryDescriptor) error{ InvalidMemoryMap, TooManyRegions }!usize {
    var n: usize = 0;
    for (map) |desc| {
        if (desc.type != .conventional_memory) continue;
        if (n >= out.len) return error.TooManyRegions;
        const start = desc.physical_start;
        const size = std.math.mul(u64, desc.number_of_pages, 4096) catch return error.InvalidMemoryMap;
        const end = std.math.add(u64, start, size) catch return error.InvalidMemoryMap;
        if (size == 0) continue;
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
    const n = try fromUefiMemoryMap(&out, &map);
    try std.testing.expectEqual(@as(usize, 1), n);
    try std.testing.expectEqual(@as(u64, 0x1000), out[0].start);
    try std.testing.expectEqual(@as(u64, 0x1000 + 2 * 4096), out[0].end);
}
