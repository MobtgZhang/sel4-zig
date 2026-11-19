//! Boot module mount shared by privileged bootstrap services.
const handoff = @import("../boot/handoff.zig");
const image = @import("image.zig");
const memory = @import("../platform/memory.zig");
pub var root: image.FileSystem = .{ .archive = .{} };
pub fn mount(h: *const handoff.BootHandoff) !void {
    if (h.ramdisk_size == 0 or h.ramdisk_size > 128 * 1024 * 1024 or h.ramdisk_address == 0) return error.MissingSystemImage;
    const end = @import("std").math.add(u64, h.ramdisk_address, h.ramdisk_size) catch return error.InvalidSystemImage;
    if (comptime @import("builtin").cpu.arch == .x86_64) {
        if (end > 0x1_0000_0000) return error.InvalidSystemImage;
    }
    const address = memory.directAddress(h.ramdisk_address);
    root = try image.FileSystem.mount(@as([*]const u8, @ptrFromInt(address))[0..@intCast(h.ramdisk_size)]);
    _ = try root.fileSize("/system/config/os-release");
}

/// Borrow contiguous data, or materialize fragmented/sparse payloads in owned
/// physical pages. The caller releases the temporary file after loading its ELF.
pub const BootFile = struct {
    bytes: []const u8,
    lease: ?memory.Lease = null,
    pub fn deinit(self: BootFile) void {
        if (self.lease) |lease| @import("../platform/runtime.zig").pages.release(lease) catch unreachable;
    }
};
pub fn openBootFile(path: []const u8, maximum: usize) !BootFile {
    const size = try root.fileSize(path);
    if (size > maximum) return error.FileTooLarge;
    const bytes = root.read(path) catch |err| switch (err) {
        error.NonContiguousFile => {
            const pool = &@import("../platform/runtime.zig").pages;
            const lease = try pool.allocatePages((@as(usize, @intCast(size)) + 4095) / 4096, 1);
            errdefer pool.release(lease) catch unreachable;
            const output = lease.bytes()[0..@intCast(size)];
            if (try root.readAt(path, 0, output) != size) return error.InvalidSystemImage;
            return .{ .bytes = output, .lease = lease };
        },
        else => return err,
    };
    return .{ .bytes = bytes };
}
const Cached = struct { path: [128]u8, length: usize, file: BootFile };
var cache: [8]Cached = undefined;
var cached: usize = 0;
/// Display fonts outlive bootstrap. Keep their leases for the kernel lifetime.
/// Calls are serialized by the bootstrap path or the kernel entry lock.
pub fn font(path: []const u8) ![]const u8 {
    const std = @import("std");
    if (path.len > 128) return error.InvalidPath;
    for (cache[0..cached]) |entry| if (std.mem.eql(u8, entry.path[0..entry.length], path)) return entry.file.bytes;
    if (cached == cache.len) return error.TooManyFonts;
    const file = try openBootFile(path, 8 * 1024 * 1024);
    cache[cached] = .{ .path = undefined, .length = path.len, .file = file };
    @memcpy(cache[cached].path[0..path.len], path);
    cached += 1;
    return file.bytes;
}
