//! Own physical storage for an initial task independently of its CPU page tables.
//! Failed task construction rolls back every allocation; user pages start zeroed.
const std = @import("std");
const memory = @import("../platform/memory.zig");
pub const Storage = struct {
    pool: *memory.PagePool,
    image: memory.Lease,
    stack: memory.Lease,
    tables: memory.Lease,
    pub fn init(pool: *memory.PagePool, image_bytes: usize, stack_bytes: usize, table_pages: usize) !Storage {
        const rounded_image = std.math.add(usize, image_bytes, 4095) catch return error.InvalidAllocation;
        const rounded_stack = std.math.add(usize, stack_bytes, 4095) catch return error.InvalidAllocation;
        const image = try pool.allocatePages(rounded_image / 4096, 1);
        errdefer pool.release(image) catch unreachable;
        const stack = try pool.allocatePages(rounded_stack / 4096, 1);
        errdefer pool.release(stack) catch unreachable;
        const tables = try pool.allocatePages(table_pages, 1);
        @memset(image.bytes(), 0);
        @memset(stack.bytes(), 0);
        @memset(tables.bytes(), 0);
        return .{ .pool = pool, .image = image, .stack = stack, .tables = tables };
    }
    /// The caller must first stop the task and deactivate its address space.
    pub fn deinit(self: *Storage) void {
        @memset(self.image.bytes(), 0);
        @memset(self.stack.bytes(), 0);
        @memset(self.tables.bytes(), 0);
        self.pool.release(self.tables) catch unreachable;
        self.pool.release(self.stack) catch unreachable;
        self.pool.release(self.image) catch unreachable;
    }
};

test "task storage zeroes pages, rolls back failure and returns ownership on teardown" {
    var ram: [16 * 4096]u8 align(4096) = @splat(0xa5);
    var available: @import("boot_mem.zig").RegionSet = .{};
    try available.add(.{ .start = @intFromPtr(&ram), .end = @intFromPtr(&ram) + ram.len });
    var pool = try memory.PagePool.init(available);
    const before = pool.availableBytes();
    try std.testing.expectError(error.OutOfMemory, Storage.init(&pool, 4096, 4096, 16));
    try std.testing.expectEqual(before, pool.availableBytes());
    var storage = try Storage.init(&pool, 4097, 8192, 4);
    try std.testing.expectEqual(before - 8 * 4096, pool.availableBytes());
    for (storage.image.bytes()) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
    @memset(storage.image.bytes(), 0xff);
    storage.deinit();
    try std.testing.expectEqual(before, pool.availableBytes());
    for (ram[0 .. 8 * 4096]) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
}
