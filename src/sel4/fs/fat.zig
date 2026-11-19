//! Read-only FAT16/FAT32 volumes. Cluster counts determine the format; the
//! printable BPB label is never trusted. FAT12 and exFAT are separate formats.
const std = @import("std");
const names = @import("names.zig");
pub const Error = error{ InvalidFilesystem, UnsupportedFeature, NeedsRecovery, InvalidPath, NotFound, NotFile, NotDirectory, NonContiguousFile };
pub const File = struct { cluster: u32, size: u64, directory: bool, fixed_root: bool = false };
pub const Entry = struct { file: File, name: []const u8 };
pub const FileSystem = struct {
    bytes: []const u8,
    fat: []const u8,
    sector_size: u32,
    cluster_size: u32,
    cluster_count: u32,
    data_offset: u64,
    root_offset: u64,
    root_size: u32,
    root_cluster: u32,
    fat32: bool,

    pub fn mount(bytes: []const u8) Error!FileSystem {
        if (bytes.len < 512 or le(u16, bytes, 510) != 0xaa55) return error.InvalidFilesystem;
        const sector_size = le(u16, bytes, 11);
        const sectors_per_cluster = bytes[13];
        const reserved = le(u16, bytes, 14);
        const copies = bytes[16];
        const root_entries = le(u16, bytes, 17);
        const sectors: u32 = if (le(u16, bytes, 19) != 0) le(u16, bytes, 19) else le(u32, bytes, 32);
        const fat_sectors = if (le(u16, bytes, 22) != 0) le(u16, bytes, 22) else le(u32, bytes, 36);
        if (sector_size < 512 or sector_size > 4096 or !std.math.isPowerOfTwo(sector_size) or
            sectors_per_cluster == 0 or sectors_per_cluster > 128 or !std.math.isPowerOfTwo(sectors_per_cluster) or
            reserved == 0 or copies == 0 or copies > 2 or fat_sectors == 0 or @as(u64, sectors) * sector_size > bytes.len) return error.InvalidFilesystem;
        const root_sectors = (@as(u32, root_entries) * 32 + sector_size - 1) / sector_size;
        const overhead = @as(u64, reserved) + @as(u64, copies) * fat_sectors + root_sectors;
        if (overhead >= sectors) return error.InvalidFilesystem;
        const clusters: u32 = @intCast((sectors - overhead) / sectors_per_cluster);
        if (clusters < 4085) return error.UnsupportedFeature; // FAT12.
        const fat32 = clusters >= 65525;
        if (clusters > 0x0fffffed) return error.InvalidFilesystem;
        if (fat32) {
            if (root_entries != 0 or le(u16, bytes, 22) != 0 or le(u16, bytes, 42) != 0) return error.InvalidFilesystem;
        } else if (root_entries == 0 or le(u16, bytes, 22) == 0) return error.InvalidFilesystem;
        var active: u32 = 0;
        if (fat32 and le(u16, bytes, 40) & 0x80 != 0) active = le(u16, bytes, 40) & 15;
        if (active >= copies) return error.InvalidFilesystem;
        const fat_offset = (@as(u64, reserved) + @as(u64, active) * fat_sectors) * sector_size;
        const fat_length = @as(u64, fat_sectors) * sector_size;
        if (@as(u64, clusters + 2) * @as(u32, if (fat32) 4 else 2) > fat_length) return error.InvalidFilesystem;
        const fs: FileSystem = .{
            .bytes = bytes[0..@intCast(@as(u64, sectors) * sector_size)],
            .fat = bytes[@intCast(fat_offset)..][0..@intCast(fat_length)],
            .sector_size = sector_size,
            .cluster_size = @as(u32, sector_size) * sectors_per_cluster,
            .cluster_count = clusters,
            .data_offset = overhead * sector_size,
            .root_offset = (@as(u64, reserved) + @as(u64, copies) * fat_sectors) * sector_size,
            .root_size = @as(u32, root_entries) * 32,
            .root_cluster = if (fat32) le(u32, bytes, 44) else 0,
            .fat32 = fat32,
        };
        if (fat32) _ = try fs.cluster(fs.root_cluster);
        // A cleared clean-shutdown bit requires repair before this reader mounts.
        if (fat32) {
            if (le(u32, fs.fat, 4) & 0x08000000 == 0) return error.NeedsRecovery;
        } else if (le(u16, fs.fat, 2) & 0x8000 == 0) return error.NeedsRecovery;
        return fs;
    }
    fn cluster(self: *const FileSystem, number: u32) Error![]const u8 {
        if (number < 2 or number - 2 >= self.cluster_count) return error.InvalidFilesystem;
        const offset = self.data_offset + @as(u64, number - 2) * self.cluster_size;
        return self.bytes[@intCast(offset)..][0..self.cluster_size];
    }
    fn nextCluster(self: *const FileSystem, number: u32) Error!?u32 {
        _ = try self.cluster(number);
        const next = if (self.fat32) le(u32, self.fat, @as(usize, number) * 4) & 0x0fffffff else le(u16, self.fat, @as(usize, number) * 2);
        if (next >= @as(u32, if (self.fat32) 0x0ffffff8 else 0xfff8)) return null;
        _ = try self.cluster(next); // Reject free, bad and reserved chain entries.
        if (next >= @as(u32, if (self.fat32) 0x0ffffff0 else 0xfff0)) return error.InvalidFilesystem;
        return next;
    }
    fn root(self: *const FileSystem) File {
        return .{ .cluster = self.root_cluster, .size = self.root_size, .directory = true, .fixed_root = !self.fat32 };
    }
    fn validateFileChain(self: *const FileSystem, file: File) Error!void {
        const count = (file.size + self.cluster_size - 1) / self.cluster_size;
        if (count == 0) return;
        if (count > self.cluster_count) return error.InvalidFilesystem;
        var number = file.cluster;
        for (1..@intCast(count)) |_| number = try self.nextCluster(number) orelse return error.InvalidFilesystem;
        // Cycles and a size that disagrees with the allocated chain are corrupt.
        if (try self.nextCluster(number) != null) return error.InvalidFilesystem;
    }
    pub fn readAt(self: *const FileSystem, file: File, offset: u64, output: []u8) Error!usize {
        if (file.directory) return error.NotFile;
        try self.validateFileChain(file);
        if (offset >= file.size) return 0;
        const count: usize = @intCast(@min(output.len, file.size - offset));
        var number = file.cluster;
        const skipped = offset / self.cluster_size;
        if (skipped >= self.cluster_count or (file.size + self.cluster_size - 1) / self.cluster_size > self.cluster_count) return error.InvalidFilesystem;
        for (0..@intCast(skipped)) |_| number = try self.nextCluster(number) orelse return error.InvalidFilesystem;
        var within: usize = @intCast(offset % self.cluster_size);
        var done: usize = 0;
        while (done < count) {
            const bytes = try self.cluster(number);
            const length = @min(count - done, bytes.len - within);
            @memcpy(output[done..][0..length], bytes[within..][0..length]);
            done += length;
            within = 0;
            if (done < count) number = try self.nextCluster(number) orelse return error.InvalidFilesystem;
        }
        return count;
    }
    pub fn view(self: *const FileSystem, file: File) Error![]const u8 {
        if (file.directory) return error.NotFile;
        try self.validateFileChain(file);
        if (file.size == 0) return self.bytes[0..0];
        const count = (file.size + self.cluster_size - 1) / self.cluster_size;
        if (count > self.cluster_count) return error.InvalidFilesystem;
        var number = file.cluster;
        for (1..@intCast(count)) |_| {
            const next = try self.nextCluster(number) orelse return error.InvalidFilesystem;
            if (next != number + 1) return error.NonContiguousFile;
            number = next;
        }
        _ = try self.cluster(number);
        const offset = self.data_offset + @as(u64, file.cluster - 2) * self.cluster_size;
        return self.bytes[@intCast(offset)..][0..@intCast(file.size)];
    }
    pub const DirectoryIterator = struct {
        fs: *const FileSystem,
        file: File,
        cluster_number: u32,
        position: usize = 0,
        clusters_visited: u32 = 1,
        ended: bool = false,
        name: [768]u8 = undefined,
        long_name: [520]u8 = undefined,
        long_count: u8 = 0,
        expected: u8 = 0,
        checksum: u8 = 0,

        fn raw(self: *DirectoryIterator) Error!?[]const u8 {
            if (self.ended) return null;
            var bytes: []const u8 = undefined;
            if (self.file.fixed_root) {
                if (self.position >= self.file.size) return null;
                bytes = self.fs.bytes[@intCast(self.fs.root_offset)..][0..self.fs.root_size];
            } else {
                if (self.position == self.fs.cluster_size) {
                    self.cluster_number = try self.fs.nextCluster(self.cluster_number) orelse return null;
                    self.clusters_visited += 1;
                    if (self.clusters_visited > self.fs.cluster_count) return error.InvalidFilesystem;
                    self.position = 0;
                }
                bytes = try self.fs.cluster(self.cluster_number);
            }
            const entry = bytes[self.position..][0..32];
            self.position += 32;
            if (entry[0] == 0) {
                self.ended = true;
                return null;
            }
            return entry;
        }
        fn longPart(self: *DirectoryIterator, entry: []const u8) void {
            const sequence = entry[0] & 0x1f;
            if (entry[0] & 0x40 != 0) {
                self.long_count = sequence;
                self.expected = sequence;
                self.checksum = entry[13];
                @memset(&self.long_name, 0xff);
            }
            if (sequence == 0 or sequence > 20 or self.expected != sequence or entry[13] != self.checksum or entry[12] != 0 or le(u16, entry, 26) != 0) {
                self.long_count = 0;
                self.expected = 0;
                return;
            }
            const start = @as(usize, sequence - 1) * 26;
            @memcpy(self.long_name[start..][0..10], entry[1..11]);
            @memcpy(self.long_name[start + 10 ..][0..12], entry[14..26]);
            @memcpy(self.long_name[start + 22 ..][0..4], entry[28..32]);
            self.expected -= 1;
        }
        pub fn next(self: *DirectoryIterator) Error!?Entry {
            while (try self.raw()) |entry| {
                if (entry[0] == 0xe5) {
                    self.long_count = 0;
                    continue;
                }
                if (entry[11] == 0x0f) {
                    self.longPart(entry);
                    continue;
                }
                defer self.long_count = 0;
                if (entry[11] & 8 != 0) continue; // Volume label.
                var checksum: u8 = 0;
                for (entry[0..11]) |byte| checksum = ((checksum & 1) << 7) +% (checksum >> 1) +% byte;
                var name: []const u8 = undefined;
                if (self.long_count != 0 and self.expected == 0 and self.checksum == checksum) {
                    var units: usize = 0;
                    while (units < @as(usize, self.long_count) * 13 and le(u16, &self.long_name, units * 2) != 0) : (units += 1) {}
                    if (units == 0 or units > 255) return error.InvalidFilesystem;
                    name = try names.utf16(self.long_name[0 .. units * 2], &self.name);
                } else {
                    var length: usize = 0;
                    for (entry[0..8], 0..) |byte, index| {
                        if (byte == ' ') break;
                        if (byte >= 128) return error.UnsupportedFeature; // OEM code pages need an explicit codec.
                        self.name[length] = if (entry[12] & 8 != 0) std.ascii.toLower(byte) else byte;
                        if (index == 0 and byte == 5) return error.UnsupportedFeature;
                        length += 1;
                    }
                    if (entry[8] != ' ') {
                        self.name[length] = '.';
                        length += 1;
                        for (entry[8..11]) |byte| {
                            if (byte == ' ') break;
                            if (byte >= 128) return error.UnsupportedFeature;
                            self.name[length] = if (entry[12] & 16 != 0) std.ascii.toLower(byte) else byte;
                            length += 1;
                        }
                    }
                    name = self.name[0..length];
                }
                return .{ .file = .{ .cluster = @as(u32, le(u16, entry, 26)) | (if (self.fs.fat32) @as(u32, le(u16, entry, 20)) << 16 else 0), .size = le(u32, entry, 28), .directory = entry[11] & 16 != 0 }, .name = name };
            }
            return null;
        }
    };
    pub fn directory(self: *const FileSystem, file: File) Error!DirectoryIterator {
        if (!file.directory) return error.NotDirectory;
        return .{ .fs = self, .file = file, .cluster_number = file.cluster };
    }
    pub fn open(self: *const FileSystem, path: []const u8) Error!File {
        try @import("path.zig").validate(path);
        var current = self.root();
        if (path.len == 1) return current;
        var parts = std.mem.splitScalar(u8, path[1..], '/');
        while (parts.next()) |part| {
            var iterator = try self.directory(current);
            var found: ?File = null;
            while (try iterator.next()) |entry| {
                // ASCII folding covers FAT's short-name interface. Unicode
                // long names compare exactly until locale case tables exist.
                if (std.ascii.eqlIgnoreCase(entry.name, part)) {
                    found = entry.file;
                    break;
                }
            }
            current = found orelse return error.NotFound;
        }
        return current;
    }
    pub fn read(self: *const FileSystem, path: []const u8) Error![]const u8 {
        return self.view(try self.open(path));
    }
    pub fn list(self: *const FileSystem, path: []const u8, writer: anytype) !void {
        var iterator = try self.directory(try self.open(path));
        while (try iterator.next()) |entry| {
            if (std.mem.eql(u8, entry.name, ".") or std.mem.eql(u8, entry.name, "..")) continue;
            try writer.write(entry.name);
            try writer.write(if (entry.file.directory) "/\r\n" else "\r\n");
        }
    }
};
fn le(comptime T: type, bytes: []const u8, offset: usize) T {
    return std.mem.readInt(T, bytes[offset..][0..@sizeOf(T)], .little);
}
