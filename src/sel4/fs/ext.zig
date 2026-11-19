//! Read-only EXT2/3/4 reader over a bounded, immutable image.
//! Supports indirect blocks, extent trees and sparse files. Dirty journals are
//! rejected: reading uncommitted metadata without replay would hide corruption.
const std = @import("std");
pub const Error = error{ InvalidFilesystem, UnsupportedFeature, NeedsRecovery, InvalidPath, NotFound, NotFile, NotDirectory, NonContiguousFile };
pub const Inode = struct { bytes: []const u8, number: u32, size: u64, directory: bool };
pub const DirectoryEntry = struct { number: u32, name: []const u8 };

pub const FileSystem = struct {
    bytes: []const u8,
    block_size: u32,
    block_count: u64,
    inode_count: u32,
    inodes_per_group: u32,
    blocks_per_group: u32,
    inode_size: u16,
    descriptor_size: u16,
    first_data_block: u32,
    file_type: bool,
    pub fn mount(bytes: []const u8) Error!FileSystem {
        if (bytes.len < 2048) return error.InvalidFilesystem;
        const super = bytes[1024..2048];
        if (le(u16, super, 56) != 0xef53) return error.InvalidFilesystem;
        const incompat = le(u32, super, 96);
        const read_only = le(u32, super, 100);
        if (incompat & 4 != 0 or le(u16, super, 58) & 1 == 0 or le(u32, super, 232) != 0 or read_only & 0x10000 != 0) return error.NeedsRecovery;
        if (read_only & 0x200 != 0) return error.UnsupportedFeature; // BIGALLOC uses cluster allocation rules.
        // CSUM_SEED changes checksum initialization, not block addressing.
        // Metadata checksums are not verified by this read-only bootstrap reader.
        if (incompat & ~@as(u32, 0x22c2) != 0) return error.UnsupportedFeature;
        if (le(u32, super, 24) > 2) return error.UnsupportedFeature;
        const block_size = @as(u32, 1024) << @as(u5, @intCast(le(u32, super, 24)));
        const revision = le(u32, super, 76);
        if (revision > 1) return error.UnsupportedFeature;
        const inode_size = if (revision == 0) 128 else le(u16, super, 88);
        const descriptor_size = if (incompat & 0x80 == 0) 32 else le(u16, super, 254);
        const block_count = @as(u64, le(u32, super, 4)) | (if (incompat & 0x80 != 0) @as(u64, le(u32, super, 336)) << 32 else 0);
        const inodes_per_group = le(u32, super, 40);
        const blocks_per_group = le(u32, super, 32);
        if (block_count == 0 or block_count > bytes.len / block_size or inodes_per_group == 0 or blocks_per_group == 0 or
            inode_size < 128 or inode_size > block_size or !std.math.isPowerOfTwo(inode_size) or
            descriptor_size < 32 or descriptor_size > block_size or !std.math.isPowerOfTwo(descriptor_size)) return error.InvalidFilesystem;
        const fs: FileSystem = .{ .bytes = bytes, .block_size = block_size, .block_count = block_count, .inode_count = le(u32, super, 0), .inodes_per_group = inodes_per_group, .blocks_per_group = blocks_per_group, .inode_size = inode_size, .descriptor_size = descriptor_size, .first_data_block = le(u32, super, 20), .file_type = incompat & 2 != 0 };
        if (fs.first_data_block != @intFromBool(block_size == 1024)) return error.InvalidFilesystem;
        const root = try fs.inode(2);
        if (!root.directory) return error.InvalidFilesystem;
        return fs;
    }
    fn slice(self: *const FileSystem, offset: u64, length: usize) Error![]const u8 {
        if (offset > self.bytes.len or length > self.bytes.len - offset) return error.InvalidFilesystem;
        return self.bytes[@intCast(offset)..][0..length];
    }
    fn block(self: *const FileSystem, number: u64) Error![]const u8 {
        if (number >= self.block_count) return error.InvalidFilesystem;
        return self.slice(number * self.block_size, self.block_size);
    }
    pub fn inode(self: *const FileSystem, number: u32) Error!Inode {
        if (number == 0 or number > self.inode_count) return error.InvalidFilesystem;
        const group = (number - 1) / self.inodes_per_group;
        if (group >= (self.block_count - self.first_data_block + self.blocks_per_group - 1) / self.blocks_per_group) return error.InvalidFilesystem;
        const descriptor = try self.slice(@as(u64, self.first_data_block + 1) * self.block_size + @as(u64, group) * self.descriptor_size, self.descriptor_size);
        const table = @as(u64, le(u32, descriptor, 8)) | (if (self.descriptor_size >= 64) @as(u64, le(u32, descriptor, 40)) << 32 else 0);
        if (table == 0 or table >= self.block_count) return error.InvalidFilesystem;
        const record = try self.slice(table * self.block_size + @as(u64, (number - 1) % self.inodes_per_group) * self.inode_size, self.inode_size);
        const kind = le(u16, record, 0) & 0xf000;
        if (kind != 0x4000 and kind != 0x8000) return error.UnsupportedFeature;
        if (le(u32, record, 32) & 0x10000000 != 0) return error.UnsupportedFeature; // Inline data.
        const size = @as(u64, le(u32, record, 4)) | (@as(u64, le(u32, record, 108)) << 32);
        // Bound traversal even if a corrupt inode advertises an enormous sparse file.
        if (size > self.bytes.len) return error.InvalidFilesystem;
        return .{ .bytes = record, .number = number, .size = size, .directory = kind == 0x4000 };
    }
    fn extentBlock(self: *const FileSystem, node: []const u8, logical: u32, expected_depth: ?u16) Error!u64 {
        if (node.len < 12 or le(u16, node, 0) != 0xf30a) return error.InvalidFilesystem;
        const entries = le(u16, node, 2);
        const maximum = le(u16, node, 4);
        const depth = le(u16, node, 6);
        if (entries > maximum or maximum > (node.len - 12) / 12 or depth > 5 or (expected_depth != null and depth != expected_depth.?)) return error.InvalidFilesystem;
        var previous: ?u32 = null;
        var child: u64 = 0;
        for (0..entries) |index| {
            const entry = node[12 + index * 12 ..][0..12];
            const start = le(u32, entry, 0);
            if (previous != null and start <= previous.?) return error.InvalidFilesystem;
            previous = start;
            if (depth != 0) {
                if (start <= logical) child = @as(u64, le(u32, entry, 4)) | (@as(u64, le(u16, entry, 8)) << 32);
                continue;
            }
            const raw_length = le(u16, entry, 4);
            const length: u32 = if (raw_length > 32768) raw_length - 32768 else raw_length;
            if (length == 0 or @as(u64, start) + length > 0x1_0000_0000) return error.InvalidFilesystem;
            if (logical < start or logical - start >= length) continue;
            if (raw_length > 32768) return 0; // Unwritten extents read as zeroes.
            const physical = @as(u64, le(u32, entry, 8)) | (@as(u64, le(u16, entry, 6)) << 32);
            if (physical == 0 or physical + length > self.block_count) return error.InvalidFilesystem;
            return physical + logical - start;
        }
        if (depth == 0 or child == 0) return 0;
        return self.extentBlock(try self.block(child), logical, depth - 1);
    }
    pub fn dataBlock(self: *const FileSystem, file: Inode, logical: u32) Error!u64 {
        if (le(u32, file.bytes, 32) & 0x80000 != 0) return self.extentBlock(file.bytes[40..100], logical, null);
        if (logical < 12) return le(u32, file.bytes, 40 + @as(usize, logical) * 4);
        const pointers: u64 = self.block_size / 4;
        var index: u64 = logical - 12;
        var span = pointers;
        var levels: u32 = 1;
        while (index >= span and levels < 3) : (levels += 1) {
            index -= span;
            span *= pointers;
        }
        if (index >= span) return error.InvalidFilesystem;
        var physical: u64 = le(u32, file.bytes, 88 + @as(usize, levels - 1) * 4);
        while (levels != 0) : (levels -= 1) {
            if (physical == 0) return 0;
            span /= pointers;
            const entries = try self.block(physical);
            physical = le(u32, entries, @intCast((index / span) * 4));
            index %= span;
        }
        if (physical >= self.block_count) return error.InvalidFilesystem;
        return physical;
    }
    pub fn readAt(self: *const FileSystem, file: Inode, offset: u64, output: []u8) Error!usize {
        if (file.directory) return error.NotFile;
        if (offset >= file.size) return 0;
        const count: usize = @intCast(@min(output.len, file.size - offset));
        var done: usize = 0;
        while (done < count) {
            const position = offset + done;
            const within: usize = @intCast(position % self.block_size);
            const length = @min(count - done, self.block_size - within);
            const physical = try self.dataBlock(file, @intCast(position / self.block_size));
            if (physical == 0) @memset(output[done..][0..length], 0) else @memcpy(output[done..][0..length], (try self.block(physical))[within..][0..length]);
            done += length;
        }
        return count;
    }
    /// Boot clients borrow an immutable slice. Fragmented files use readAt instead.
    pub fn view(self: *const FileSystem, file: Inode) Error![]const u8 {
        if (file.directory) return error.NotFile;
        if (file.size == 0) return self.bytes[0..0];
        const first = try self.dataBlock(file, 0);
        if (first == 0) return error.NonContiguousFile;
        const count = (file.size + self.block_size - 1) / self.block_size;
        for (1..@intCast(count)) |index| {
            if (try self.dataBlock(file, @intCast(index)) != first + index) return error.NonContiguousFile;
        }
        return self.slice(first * self.block_size, @intCast(file.size));
    }
    pub const DirectoryIterator = struct {
        fs: *const FileSystem,
        directory: Inode,
        position: u64 = 0,
        pub fn next(self: *DirectoryIterator) Error!?DirectoryEntry {
            while (self.position < self.directory.size) {
                const physical = try self.fs.dataBlock(self.directory, @intCast(self.position / self.fs.block_size));
                if (physical == 0) return error.InvalidFilesystem;
                const bytes = try self.fs.block(physical);
                const offset: usize = @intCast(self.position % self.fs.block_size);
                if (bytes.len - offset < 8) return error.InvalidFilesystem;
                const entry = bytes[offset..];
                const length = le(u16, entry, 4);
                const name_length = if (self.fs.file_type) entry[6] else le(u16, entry, 6);
                if (length < 8 or length % 4 != 0 or length > entry.len or length > self.directory.size - self.position or name_length > length - 8) return error.InvalidFilesystem;
                self.position += length;
                const number = le(u32, entry, 0);
                if (number == 0) continue;
                if (number > self.fs.inode_count or name_length == 0) return error.InvalidFilesystem;
                const name = entry[8..][0..name_length];
                if (std.mem.indexOfScalar(u8, name, 0) != null or std.mem.indexOfScalar(u8, name, '/') != null) return error.InvalidFilesystem;
                return .{ .number = number, .name = name };
            }
            return null;
        }
    };
    pub fn directory(self: *const FileSystem, file: Inode) Error!DirectoryIterator {
        if (!file.directory) return error.NotDirectory;
        return .{ .fs = self, .directory = file };
    }
    pub fn open(self: *const FileSystem, path: []const u8) Error!Inode {
        try @import("path.zig").validate(path);
        var current = try self.inode(2);
        if (path.len == 1) return current;
        var parts = std.mem.splitScalar(u8, path[1..], '/');
        while (parts.next()) |part| {
            var iterator = try self.directory(current);
            var found: ?u32 = null;
            while (try iterator.next()) |entry| {
                if (std.mem.eql(u8, entry.name, part)) {
                    found = entry.number;
                    break;
                }
            }
            current = try self.inode(found orelse return error.NotFound);
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
            const child = try self.inode(entry.number);
            try writer.write(entry.name);
            try writer.write(if (child.directory) "/\r\n" else "\r\n");
        }
    }
};
fn le(comptime T: type, bytes: []const u8, offset: usize) T {
    return std.mem.readInt(T, bytes[offset..][0..@sizeOf(T)], .little);
}
