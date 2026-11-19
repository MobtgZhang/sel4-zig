//! Immutable USTAR filesystem. File slices borrow the reserved boot module.
//! Validation completes before the mount becomes visible to callers.
const std = @import("std");
pub const Error = error{ InvalidArchive, InvalidPath, TooManyFiles, DuplicatePath, NotFound, NotFile };
pub const Entry = struct { path: []const u8, data: []const u8, directory: bool };
pub const FileSystem = struct {
    entries: [128]Entry = undefined,
    count: usize = 0,
    pub fn mount(bytes: []const u8) Error!FileSystem {
        if (bytes.len < 1024 or bytes.len % 512 != 0) return error.InvalidArchive;
        var fs: FileSystem = .{};
        var offset: usize = 0;
        while (offset + 1024 <= bytes.len) {
            const header = bytes[offset..][0..512];
            if (allZero(header)) {
                if (!allZero(bytes[offset..])) return error.InvalidArchive;
                return fs;
            }
            if (!std.mem.eql(u8, header[257..263], "ustar\x00") or header[345] != 0) return error.InvalidArchive;
            var sum: usize = 0;
            for (header, 0..) |byte, i| sum += if (i >= 148 and i < 156) 32 else byte;
            if (sum != try octal(header[148..156])) return error.InvalidArchive;
            const end = std.mem.indexOfScalar(u8, header[0..100], 0) orelse return error.InvalidArchive;
            var path = header[0..end];
            const directory = header[156] == '5';
            if (!directory and header[156] != '0' and header[156] != 0) return error.InvalidArchive;
            if (directory and std.mem.endsWith(u8, path, "/")) path = path[0 .. path.len - 1];
            try validPath(path);
            const size = try octal(header[124..136]);
            if (directory and size != 0) return error.InvalidArchive;
            if (size > bytes.len - offset - 512) return error.InvalidArchive;
            if (fs.count == fs.entries.len) return error.TooManyFiles;
            for (fs.entries[0..fs.count]) |old| if (std.mem.eql(u8, old.path, path)) return error.DuplicatePath;
            fs.entries[fs.count] = .{ .path = path, .data = bytes[offset + 512 ..][0..size], .directory = directory };
            fs.count += 1;
            offset += 512 + std.mem.alignForward(usize, size, 512);
        }
        return error.InvalidArchive;
    }
    pub fn lookup(self: *const FileSystem, absolute: []const u8) Error!Entry {
        if (absolute.len < 2 or absolute[0] != '/') return error.InvalidPath;
        const path = absolute[1..];
        try validPath(path);
        for (self.entries[0..self.count]) |entry| if (std.mem.eql(u8, path, entry.path)) return entry;
        return error.NotFound;
    }
    pub fn read(self: *const FileSystem, absolute: []const u8) Error![]const u8 {
        const entry = try self.lookup(absolute);
        if (entry.directory) return error.NotFile;
        return entry.data;
    }
    pub fn fileSize(self: *const FileSystem, path: []const u8) Error!u64 {
        return (try self.read(path)).len;
    }
    pub fn readAt(self: *const FileSystem, path: []const u8, offset: u64, output: []u8) Error!usize {
        const bytes = try self.read(path);
        if (offset >= bytes.len) return 0;
        const count = @min(output.len, bytes.len - @as(usize, @intCast(offset)));
        @memcpy(output[0..count], bytes[@intCast(offset)..][0..count]);
        return count;
    }
    pub fn list(self: *const FileSystem, path: []const u8, writer: anytype) !void {
        if (!std.mem.eql(u8, path, "/")) {
            if (!(try self.lookup(path)).directory) return error.NotDirectory;
        }
        var buffer: [128]u8 = undefined;
        const prefix = if (std.mem.eql(u8, path, "/")) "" else try std.fmt.bufPrint(&buffer, "{s}/", .{path[1..]});
        for (self.entries[0..self.count]) |entry| {
            if (!std.mem.startsWith(u8, entry.path, prefix)) continue;
            const name = entry.path[prefix.len..];
            if (name.len == 0 or std.mem.indexOfScalar(u8, name, '/') != null) continue;
            try writer.write(name);
            try writer.write(if (entry.directory) "/\r\n" else "\r\n");
        }
    }
};
fn allZero(bytes: []const u8) bool {
    for (bytes) |b| if (b != 0) return false;
    return true;
}
fn octal(bytes: []const u8) Error!usize {
    const number = std.mem.trim(u8, bytes, " \x00");
    if (number.len == 0) return error.InvalidArchive;
    var value: usize = 0;
    for (number) |digit| {
        if (digit < '0' or digit > '7') return error.InvalidArchive;
        value = std.math.mul(usize, value, 8) catch return error.InvalidArchive;
        value = std.math.add(usize, value, digit - '0') catch return error.InvalidArchive;
    }
    return value;
}
fn validPath(path: []const u8) Error!void {
    if (path.len == 0 or path.len > 99 or path[0] == '/') return error.InvalidPath;
    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return error.InvalidPath;
        for (part) |byte| if (byte < 32 or byte > 126 or byte == '\\') return error.InvalidPath;
    }
}

test "archive rejects truncated input, traversal, bad checksums and duplicate files" {
    try std.testing.expectError(error.InvalidArchive, FileSystem.mount(&.{}));
    var archive: [3072]u8 = @splat(0);
    @memcpy(archive[0..8], "test.txt");
    @memcpy(archive[124..136], "00000000003\x00");
    @memcpy(archive[257..263], "ustar\x00");
    @memcpy(archive[512..515], "abc");
    archive[156] = '0';
    try std.testing.expectError(error.InvalidArchive, FileSystem.mount(&archive));
    var sum: usize = 8 * 32;
    for (archive[0..512]) |b| sum += b;
    _ = try std.fmt.bufPrint(archive[148..156], "{o:0>6}\x00 ", .{sum});
    const fs = try FileSystem.mount(&archive);
    try std.testing.expectEqualStrings("abc", try fs.read("/test.txt"));
    try std.testing.expectError(error.InvalidPath, fs.read("/../test.txt"));
    @memcpy(archive[1024..1536], archive[0..512]);
    @memcpy(archive[1536..1539], "abc");
    try std.testing.expectError(error.DuplicatePath, FileSystem.mount(&archive));
}
