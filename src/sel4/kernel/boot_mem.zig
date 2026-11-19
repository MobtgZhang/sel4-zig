//! Canonical physical region sets and boot allocation.
//! Free RAM and reserved ranges are distinct sets; intervals are half-open.
const std = @import("std");
pub const PRegion = struct {
    start: u64,
    end: u64,
    pub fn isEmpty(self: PRegion) bool {
        return self.start >= self.end;
    }
};
pub const max_reserved: usize = 128;

/// Merge overlaps and adjacency in a set already sorted by start address.
pub fn mergeRegions(regions: []PRegion, count: *usize) void {
    std.debug.assert(count.* <= regions.len);
    if (count.* == 0) return;
    var out: usize = 0;
    for (regions[1..count.*]) |region| {
        if (region.start <= regions[out].end) {
            regions[out].end = @max(regions[out].end, region.end);
        } else {
            out += 1;
            regions[out] = region;
        }
    }
    count.* = out + 1;
}

/// Union with a sorted, non-overlapping set. Capacity failures leave it intact.
pub fn reserveRegion(regions: []PRegion, count: *usize, region: PRegion) bool {
    if (count.* > regions.len) return false;
    if (region.isEmpty()) return true;
    var first: usize = 0;
    while (first < count.* and regions[first].end < region.start) : (first += 1) {}
    var last = first;
    var joined = region;
    while (last < count.* and regions[last].start <= joined.end) : (last += 1) {
        joined.start = @min(joined.start, regions[last].start);
        joined.end = @max(joined.end, regions[last].end);
    }
    if (first == last) {
        if (count.* == regions.len) return false;
        std.mem.copyBackwards(PRegion, regions[first + 1 .. count.* + 1], regions[first..count.*]);
        count.* += 1;
    } else {
        std.mem.copyForwards(PRegion, regions[first + 1 .. count.* - (last - first) + 1], regions[last..count.*]);
        count.* -= last - first - 1;
    }
    regions[first] = joined;
    return true;
}

pub const RegionSet = struct {
    regions: [max_reserved]PRegion = undefined,
    count: usize = 0,
    pub fn slice(self: *const RegionSet) []const PRegion {
        return self.regions[0..self.count];
    }
    pub fn add(self: *RegionSet, region: PRegion) error{TooManyRegions}!void {
        if (!reserveRegion(&self.regions, &self.count, region)) return error.TooManyRegions;
    }
    /// Remove a reservation from usable memory, including splitting intervals.
    pub fn subtract(self: *RegionSet, reserved: PRegion) error{TooManyRegions}!void {
        if (reserved.isEmpty()) return;
        var result: RegionSet = .{};
        for (self.slice()) |region| {
            if (reserved.end <= region.start or reserved.start >= region.end) {
                try result.add(region);
            } else {
                if (region.start < reserved.start) try result.add(.{ .start = region.start, .end = reserved.start });
                if (reserved.end < region.end) try result.add(.{ .start = reserved.end, .end = region.end });
            }
        }
        self.* = result;
    }
    /// Allocate from the first suitable interval after alignment.
    pub fn allocate(self: *RegionSet, size_bits: u6) error{ OutOfMemory, TooManyRegions }!u64 {
        const size = @as(u64, 1) << size_bits;
        return self.allocateRange(size, size) catch |err| switch (err) {
            error.InvalidAllocation => unreachable,
            error.OutOfMemory => return error.OutOfMemory,
            error.TooManyRegions => return error.TooManyRegions,
        };
    }
    pub fn allocateRange(self: *RegionSet, size: u64, alignment: u64) error{ InvalidAllocation, OutOfMemory, TooManyRegions }!u64 {
        if (size == 0 or !std.math.isPowerOfTwo(alignment)) return error.InvalidAllocation;
        for (self.slice()) |region| {
            const rounded = std.math.add(u64, region.start, alignment - 1) catch continue;
            const start = rounded & ~(alignment - 1);
            if (start > region.end or size > region.end - start) continue;
            try self.subtract(.{ .start = start, .end = start + size });
            return start;
        }
        return error.OutOfMemory;
    }
};

test "region union merges overlaps even at full capacity" {
    var regions: [2]PRegion = undefined;
    var count: usize = 0;
    try std.testing.expect(reserveRegion(&regions, &count, .{ .start = 10, .end = 20 }));
    try std.testing.expect(reserveRegion(&regions, &count, .{ .start = 30, .end = 40 }));
    try std.testing.expect(reserveRegion(&regions, &count, .{ .start = 15, .end = 35 }));
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqual(PRegion{ .start = 10, .end = 40 }, regions[0]);
}
test "region union capacity failure is atomic" {
    var regions = [_]PRegion{.{ .start = 10, .end = 20 }};
    var count: usize = 1;
    try std.testing.expect(!reserveRegion(&regions, &count, .{ .start = 30, .end = 40 }));
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqual(@as(u64, 20), regions[0].end);
}
test "free memory excludes reservations and aligns allocations" {
    var set: RegionSet = .{};
    try set.add(.{ .start = 1, .end = 0x10000 });
    try set.subtract(.{ .start = 0x2000, .end = 0x5000 });
    try std.testing.expectEqual(@as(usize, 2), set.count);
    try std.testing.expectEqual(@as(u64, 0x1000), try set.allocate(12));
    try std.testing.expectEqual(@as(u64, 0x5000), try set.allocate(12));
    try set.subtract(.{ .start = 0, .end = 0x10000 });
    try std.testing.expectEqual(@as(usize, 0), set.count);
    try std.testing.expectError(error.OutOfMemory, set.allocate(12));
}
test "allocation skips unalignable addresses near word limit" {
    var set: RegionSet = .{};
    try set.add(.{ .start = std.math.maxInt(u64) - 2, .end = std.math.maxInt(u64) });
    try std.testing.expectError(error.OutOfMemory, set.allocate(12));
}
