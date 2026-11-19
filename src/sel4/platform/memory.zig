//! Physical page ownership independent of the CPU's virtual mapping convention.
//! Leases prevent double-free, stale release and freeing firmware/device storage.
const std = @import("std");
const regions = @import("../kernel/boot_mem.zig");
const SpinLock = @import("sync.zig").SpinLock;
pub const Lease = struct {
    address: u64,
    generation: u64,
    slot: usize,
    page_count: usize,
    pub fn bytes(self: Lease) []align(4096) u8 {
        const pointer: [*]align(4096) u8 = @ptrFromInt(directAddress(self.address));
        return pointer[0 .. self.page_count * 4096];
    }
};
pub const PagePool = struct {
    free: regions.RegionSet = .{},
    leases: [256]?Lease = @splat(null),
    generation: u64 = 0,
    lock: SpinLock = .{},

    pub fn init(available: regions.RegionSet) !PagePool {
        var result: PagePool = .{};
        for (available.slice()) |region| {
            const rounded = std.math.add(u64, region.start, 4095) catch continue;
            const start = rounded & ~@as(u64, 4095);
            const end = region.end & ~@as(u64, 4095);
            if (start < end) try result.free.add(.{ .start = start, .end = end });
        }
        return result;
    }
    pub fn allocate(self: *PagePool) !Lease {
        return self.allocatePages(1, 1);
    }
    /// Allocate contiguous pages, preserving holes and ownership on failure.
    pub fn allocatePages(self: *PagePool, count: usize, alignment_pages: usize) !Lease {
        if (count == 0 or !std.math.isPowerOfTwo(alignment_pages)) return error.InvalidAllocation;
        const size = std.math.mul(u64, count, 4096) catch return error.InvalidAllocation;
        const alignment = std.math.mul(u64, alignment_pages, 4096) catch return error.InvalidAllocation;
        self.lock.lock();
        defer self.lock.unlock();
        var slot: usize = 0;
        while (slot < self.leases.len and self.leases[slot] != null) : (slot += 1) {}
        if (slot == self.leases.len) return error.TooManyLeases;
        if (self.generation == std.math.maxInt(u64)) return error.GenerationExhausted;
        const address = try self.free.allocateRange(size, alignment);
        self.generation += 1;
        const lease = Lease{ .address = address, .generation = self.generation, .slot = slot, .page_count = count };
        self.leases[slot] = lease;
        return lease;
    }
    pub fn release(self: *PagePool, lease: Lease) !void {
        self.lock.lock();
        defer self.lock.unlock();
        if (lease.slot >= self.leases.len) return error.InvalidLease;
        const live = self.leases[lease.slot] orelse return error.InvalidLease;
        if (live.address != lease.address or live.generation != lease.generation or live.page_count != lease.page_count) return error.InvalidLease;
        try self.free.add(.{ .start = live.address, .end = live.address + live.page_count * 4096 });
        self.leases[lease.slot] = null;
    }
    pub fn availableBytes(self: *PagePool) u64 {
        self.lock.lock();
        defer self.lock.unlock();
        var total: u64 = 0;
        for (self.free.slice()) |region| total += region.end - region.start;
        return total;
    }
};
pub fn directAddress(physical: u64) usize {
    return @import("../arch/mod.zig").backend.directAddress(physical);
}

test "physical pool preserves holes, rejects stale leases and recovers all pages" {
    var available: regions.RegionSet = .{};
    try available.add(.{ .start = 1, .end = 0x9000 });
    try available.subtract(.{ .start = 0x2000, .end = 0x7000 });
    var pool = try PagePool.init(available);
    const before = pool.availableBytes();
    const a = try pool.allocate();
    const b = try pool.allocate();
    try std.testing.expectEqual(@as(u64, 0x1000), a.address);
    try std.testing.expectEqual(@as(u64, 0x7000), b.address);
    try pool.release(a);
    const replacement = try pool.allocate();
    try std.testing.expectError(error.InvalidLease, pool.release(a));
    try pool.release(replacement);
    try pool.release(b);
    try std.testing.expectError(error.InvalidLease, pool.release(b));
    try std.testing.expectEqual(before, pool.availableBytes());
}
test "physical pool serializes concurrent allocation and release" {
    var available: regions.RegionSet = .{};
    try available.add(.{ .start = 0x1000, .end = 0x100000 });
    var pool = try PagePool.init(available);
    const Worker = struct {
        fn run(p: *PagePool) void {
            for (0..1000) |_| {
                const lease = p.allocate() catch @panic("allocate failed");
                p.release(lease) catch @panic("release failed");
            }
        }
    };
    var threads: [4]std.Thread = undefined;
    for (&threads) |*thread| thread.* = try std.Thread.spawn(.{}, Worker.run, .{&pool});
    for (threads) |thread| thread.join();
    try std.testing.expectEqual(@as(u64, 0xff000), pool.availableBytes());
}

test "contiguous page leases enforce alignment, ownership and transactional failure" {
    var available: regions.RegionSet = .{};
    try available.add(.{ .start = 0x1000, .end = 0x20000 });
    try available.subtract(.{ .start = 0x8000, .end = 0x10000 });
    var pool = try PagePool.init(available);
    const before = pool.availableBytes();
    const lease = try pool.allocatePages(4, 4);
    try std.testing.expectEqual(@as(u64, 0x4000), lease.address);
    try std.testing.expectEqual(before - 0x4000, pool.availableBytes());
    var forged = lease;
    forged.page_count = 8;
    try std.testing.expectError(error.InvalidLease, pool.release(forged));
    try std.testing.expectError(error.InvalidAllocation, pool.allocatePages(0, 1));
    try std.testing.expectError(error.InvalidAllocation, pool.allocatePages(1, 3));
    try std.testing.expectError(error.OutOfMemory, pool.allocatePages(17, 1));
    try std.testing.expectEqual(before - 0x4000, pool.availableBytes());
    try pool.release(lease);
    try std.testing.expectEqual(before, pool.availableBytes());
}
