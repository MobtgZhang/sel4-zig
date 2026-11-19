//! Bounded, read-only NTFS 3.x image reader. FILE records are copied and their
//! update-sequence arrays are verified before interpreting any attributes.
//! Directory lookup scans allocated base MFT records and validates parent
//! sequence numbers. It does not depend on the ordering of the $I30 index.
//! Compression, encryption and attribute-list extension records are rejected.
const std = @import("std");
const names = @import("names.zig");
pub const Error = error{ InvalidFilesystem, UnsupportedFeature, NeedsRecovery, InvalidPath, NotFound, NotFile, NotDirectory, NonContiguousFile };
const max_record = 4096;
const max_runs = 128;
const reference_mask = 0x0000ffffffffffff;
pub const File = struct { number: u64, sequence: u16, size: u64, directory: bool };
pub const Entry = struct { number: u64, sequence: u16, directory: bool, name: []const u8 };
const Run = struct { start: u64, count: u64, physical: ?u64 };
const Stream = struct {
    runs: [max_runs]Run = undefined,
    count: usize = 0,
    size: u64 = 0,
    initialized: u64 = 0,
    resident: ?usize = null,
};
const Attribute = struct { bytes: []const u8, offset: usize, kind: u32 };
const Attributes = struct {
    bytes: []const u8,
    position: usize,
    fn init(record: []const u8) Error!Attributes {
        const used = le(u32, record, 24);
        const offset = le(u16, record, 20);
        if (used > record.len or used < 48 or offset < 42 or offset % 8 != 0 or offset > used - 4) return error.InvalidFilesystem;
        return .{ .bytes = record[0..used], .position = offset };
    }
    fn next(self: *Attributes) Error!?Attribute {
        if (self.position > self.bytes.len - 4) return error.InvalidFilesystem;
        const kind = le(u32, self.bytes, self.position);
        if (kind == 0xffffffff) return null;
        const rest = self.bytes[self.position..];
        if (rest.len < 24) return error.InvalidFilesystem;
        const length = le(u32, rest, 4);
        const minimum: u32 = if (rest[8] == 0) 24 else 64;
        if (rest[8] > 1 or length < minimum or length % 8 != 0 or length > rest.len) return error.InvalidFilesystem;
        const name_offset = le(u16, rest, 10);
        if (rest[9] != 0 and (name_offset < minimum or @as(u32, name_offset) + @as(u32, rest[9]) * 2 > length)) return error.InvalidFilesystem;
        const offset = self.position;
        self.position += length;
        return .{ .bytes = rest[0..length], .offset = offset, .kind = kind };
    }
};
pub const FileSystem = struct {
    bytes: []const u8,
    sector_size: u32,
    cluster_size: u32,
    cluster_count: u64,
    record_size: u32,
    mft: Stream,
    record_count: u64,

    pub fn mount(bytes: []const u8) Error!FileSystem {
        if (bytes.len < 512 or !std.mem.eql(u8, bytes[3..11], "NTFS    ") or le(u16, bytes, 510) != 0xaa55) return error.InvalidFilesystem;
        const sector_size = le(u16, bytes, 11);
        const sectors_per_cluster = bytes[13];
        const sectors = le(u64, bytes, 40);
        if (sector_size < 512 or sector_size > 4096 or !std.math.isPowerOfTwo(sector_size) or
            sectors_per_cluster == 0 or !std.math.isPowerOfTwo(sectors_per_cluster) or
            sectors < 16 or sectors > bytes.len / sector_size) return error.InvalidFilesystem;
        const cluster_size = @as(u32, sector_size) * sectors_per_cluster;
        const encoded: i8 = @bitCast(bytes[64]);
        var record_size: u32 = undefined;
        if (encoded < 0) {
            if (encoded < -12) return error.UnsupportedFeature;
            record_size = @as(u32, 1) << @as(u5, @intCast(-@as(i16, encoded)));
        } else {
            if (encoded == 0 or @as(u64, @intCast(encoded)) * cluster_size > max_record) return error.UnsupportedFeature;
            record_size = @as(u32, @intCast(encoded)) * cluster_size;
        }
        if (record_size < sector_size or record_size > max_record or record_size % sector_size != 0) return error.UnsupportedFeature;
        var fs: FileSystem = .{ .bytes = bytes[0..@intCast(sectors * sector_size)], .sector_size = sector_size, .cluster_size = cluster_size, .cluster_count = sectors / sectors_per_cluster, .record_size = record_size, .mft = .{}, .record_count = 0 };
        const mft_cluster = le(u64, bytes, 48);
        if (mft_cluster >= fs.cluster_count) return error.InvalidFilesystem;
        var storage: [max_record]u8 = undefined;
        const record = storage[0..record_size];
        @memcpy(record, try fs.slice(mft_cluster * cluster_size, record_size));
        try fs.fixup(record);
        fs.mft = try fs.dataStream(record);
        if (fs.mft.resident != null or fs.mft.size % record_size != 0 or fs.mft.initialized % record_size != 0) return error.InvalidFilesystem;
        fs.record_count = fs.mft.initialized / record_size;
        if (fs.record_count < 16) return error.InvalidFilesystem;
        for (fs.mft.runs[0..fs.mft.count]) |run| if (run.physical == null) return error.InvalidFilesystem;
        // $Volume carries the version and dirty flag. No journal is replayed.
        try fs.loadRecord(3, record);
        var attributes = try Attributes.init(record);
        var volume_information = false;
        while (try attributes.next()) |attribute| {
            if (attribute.kind != 0x70) continue;
            const value = try resident(attribute.bytes);
            if (value.len < 12 or value[8] != 3 or value[9] > 1) return error.UnsupportedFeature;
            if (le(u16, value, 10) != 0) return error.NeedsRecovery;
            volume_information = true;
        }
        if (!volume_information) return error.InvalidFilesystem;
        if (!(try fs.file(5)).directory) return error.InvalidFilesystem;
        return fs;
    }
    fn slice(self: *const FileSystem, offset: u64, length: usize) Error![]const u8 {
        if (offset > self.bytes.len or length > self.bytes.len - offset) return error.InvalidFilesystem;
        return self.bytes[@intCast(offset)..][0..length];
    }
    fn fixup(self: *const FileSystem, record: []u8) Error!void {
        if (record.len != self.record_size or !std.mem.eql(u8, record[0..4], "FILE")) return error.InvalidFilesystem;
        const offset = le(u16, record, 4);
        const count = le(u16, record, 6);
        if (count != record.len / self.sector_size + 1 or offset < 8 or offset % 2 != 0 or @as(u32, offset) + @as(u32, count) * 2 > self.sector_size - 2) return error.InvalidFilesystem;
        const sequence = le(u16, record, offset);
        for (1..count) |index| {
            const tail = index * self.sector_size - 2;
            if (le(u16, record, tail) != sequence) return error.InvalidFilesystem;
            @memcpy(record[tail..][0..2], record[offset + index * 2 ..][0..2]);
        }
        if (le(u32, record, 28) != record.len) return error.InvalidFilesystem;
    }
    fn dataStream(self: *const FileSystem, record: []const u8) Error!Stream {
        var attributes = try Attributes.init(record);
        var result: ?Stream = null;
        while (try attributes.next()) |attribute| {
            if (attribute.kind == 0x20) return error.UnsupportedFeature; // ATTRIBUTE_LIST.
            if (attribute.kind != 0x80 or attribute.bytes[9] != 0) continue; // Unnamed $DATA.
            if (result != null) return error.UnsupportedFeature;
            const bytes = attribute.bytes;
            // Sparse streams are supported; compressed and encrypted ones are not.
            if (le(u16, bytes, 12) & ~@as(u16, 0x8000) != 0) return error.UnsupportedFeature;
            if (bytes[8] == 0) {
                const value = try resident(bytes);
                result = .{ .resident = attribute.offset + le(u16, bytes, 20), .size = value.len, .initialized = value.len };
                continue;
            }
            if (le(u64, bytes, 16) != 0 or le(u16, bytes, 34) != 0) return error.UnsupportedFeature;
            var stream: Stream = .{ .size = le(u64, bytes, 48), .initialized = le(u64, bytes, 56) };
            if (stream.size > self.bytes.len or stream.initialized > stream.size) return error.InvalidFilesystem;
            var position: usize = le(u16, bytes, 32);
            if (position < 64 or position >= bytes.len) return error.InvalidFilesystem;
            var logical: u64 = 0;
            var physical: i64 = 0;
            while (bytes[position] != 0) {
                const count_bytes = bytes[position] & 15;
                const delta_bytes = bytes[position] >> 4;
                position += 1;
                if (count_bytes == 0 or count_bytes > 8 or delta_bytes > 8 or @as(usize, count_bytes) + delta_bytes >= bytes.len - position or stream.count == max_runs) return error.InvalidFilesystem;
                const count = variable(bytes[position..][0..count_bytes]);
                position += count_bytes;
                if (count == 0 or count > self.cluster_count - logical) return error.InvalidFilesystem;
                var location: ?u64 = null;
                if (delta_bytes != 0) {
                    const raw = variable(bytes[position..][0..delta_bytes]);
                    const shift: u6 = @intCast(64 - @as(u8, delta_bytes) * 8);
                    const delta = @as(i64, @bitCast(raw << shift)) >> shift;
                    physical = std.math.add(i64, physical, delta) catch return error.InvalidFilesystem;
                    if (physical < 0 or @as(u64, @intCast(physical)) >= self.cluster_count or count > self.cluster_count - @as(u64, @intCast(physical))) return error.InvalidFilesystem;
                    location = @intCast(physical);
                }
                position += delta_bytes;
                stream.runs[stream.count] = .{ .start = logical, .count = count, .physical = location };
                stream.count += 1;
                logical += count;
            }
            if ((stream.size + self.cluster_size - 1) / self.cluster_size > logical or
                (logical != 0 and le(u64, bytes, 24) != logical - 1)) return error.InvalidFilesystem;
            result = stream;
        }
        return result orelse error.NotFile;
    }
    fn readStream(self: *const FileSystem, stream: *const Stream, offset: u64, output: []u8) Error!usize {
        if (stream.resident != null) return error.InvalidFilesystem;
        if (offset >= stream.size) return 0;
        const count: usize = @intCast(@min(output.len, stream.size - offset));
        @memset(output[0..count], 0);
        for (stream.runs[0..stream.count]) |run| {
            const start = run.start * self.cluster_size;
            const end = start + run.count * self.cluster_size;
            const from = @max(offset, start);
            const to = @min(@min(offset + count, end), stream.initialized);
            if (from >= to or run.physical == null) continue;
            const destination: usize = @intCast(from - offset);
            const length: usize = @intCast(to - from);
            @memcpy(output[destination..][0..length], try self.slice(run.physical.? * self.cluster_size + from - start, length));
        }
        return count;
    }
    fn loadRecord(self: *const FileSystem, number: u64, output: []u8) Error!void {
        if (number >= self.record_count or output.len != self.record_size) return error.InvalidFilesystem;
        if (try self.readStream(&self.mft, number * self.record_size, output) != output.len) return error.InvalidFilesystem;
        try self.fixup(output);
    }
    pub fn file(self: *const FileSystem, number: u64) Error!File {
        var storage: [max_record]u8 = undefined;
        const record_bytes = storage[0..self.record_size];
        try self.loadRecord(number, record_bytes);
        if (le(u16, record_bytes, 22) & 1 == 0 or le(u64, record_bytes, 32) != 0) return error.NotFound;
        const directory_file = le(u16, record_bytes, 22) & 2 != 0;
        const size = if (directory_file) 0 else (try self.dataStream(record_bytes)).size;
        return .{ .number = number, .sequence = le(u16, record_bytes, 16), .size = size, .directory = directory_file };
    }
    pub fn readAt(self: *const FileSystem, descriptor: File, offset: u64, output: []u8) Error!usize {
        if (descriptor.directory) return error.NotFile;
        var storage: [max_record]u8 = undefined;
        const record_bytes = storage[0..self.record_size];
        try self.loadRecord(descriptor.number, record_bytes);
        const stream = try self.dataStream(record_bytes);
        if (offset >= stream.size) return 0;
        if (stream.resident) |start| {
            const count: usize = @intCast(@min(output.len, stream.size - offset));
            @memcpy(output[0..count], record_bytes[start + @as(usize, @intCast(offset)) ..][0..count]);
            return count;
        }
        return self.readStream(&stream, offset, output);
    }
    pub fn view(self: *const FileSystem, descriptor: File) Error![]const u8 {
        if (descriptor.directory) return error.NotFile;
        var storage: [max_record]u8 = undefined;
        const record_bytes = storage[0..self.record_size];
        try self.loadRecord(descriptor.number, record_bytes);
        const stream = try self.dataStream(record_bytes);
        if (stream.size == 0) return self.bytes[0..0];
        if (stream.initialized < stream.size) return error.NonContiguousFile;
        if (stream.resident) |start| {
            // A borrowed on-disk slice cannot include a sector-tail USA token.
            if ((start + stream.size - 1) / self.sector_size != start / self.sector_size or
                (start + stream.size - 1) % self.sector_size >= self.sector_size - 2) return error.NonContiguousFile;
            const mft_offset = descriptor.number * self.record_size + start;
            for (self.mft.runs[0..self.mft.count]) |run| {
                const base = run.start * self.cluster_size;
                if (mft_offset >= base and mft_offset - base + stream.size <= run.count * self.cluster_size) {
                    return self.slice(run.physical.? * self.cluster_size + mft_offset - base, @intCast(stream.size));
                }
            }
            return error.NonContiguousFile;
        }
        var first: ?u64 = null;
        for (stream.runs[0..stream.count]) |run| {
            const physical = run.physical orelse return error.NonContiguousFile;
            if (first == null) first = physical;
            if (physical != first.? + run.start) return error.NonContiguousFile;
        }
        return self.slice((first orelse return error.InvalidFilesystem) * self.cluster_size, @intCast(stream.size));
    }
    pub const DirectoryIterator = struct {
        fs: *const FileSystem,
        parent: File,
        number: u64 = 16,
        record_storage: [max_record]u8 = undefined,
        attributes: ?Attributes = null,
        name: [768]u8 = undefined,
        pub fn next(self: *DirectoryIterator) Error!?Entry {
            while (true) {
                if (self.attributes) |*attributes| {
                    while (try attributes.next()) |attribute| {
                        if (attribute.kind != 0x30) continue;
                        const value = try resident(attribute.bytes);
                        if (value.len < 66 or value[64] == 0 or @as(usize, value[64]) * 2 > value.len - 66 or value[65] > 3) return error.InvalidFilesystem;
                        const parent = le(u64, value, 0);
                        if (parent & reference_mask != self.parent.number or parent >> 48 != self.parent.sequence or value[65] == 2) continue;
                        const record_bytes = self.record_storage[0..self.fs.record_size];
                        return .{ .number = self.number - 1, .sequence = le(u16, record_bytes, 16), .directory = le(u16, record_bytes, 22) & 2 != 0, .name = try names.utf16(value[66..][0 .. @as(usize, value[64]) * 2], &self.name) };
                    }
                    self.attributes = null;
                }
                if (self.number == self.fs.record_count) return null;
                const record_bytes = self.record_storage[0..self.fs.record_size];
                // Unused MFT slots may have never contained a FILE record.
                if (try self.fs.readStream(&self.fs.mft, self.number * self.fs.record_size, record_bytes) != record_bytes.len) return error.InvalidFilesystem;
                self.number += 1;
                if (std.mem.allEqual(u8, record_bytes, 0)) continue;
                try self.fs.fixup(record_bytes);
                if (le(u16, record_bytes, 22) & 1 == 0 or le(u64, record_bytes, 32) != 0) continue;
                self.attributes = try Attributes.init(record_bytes);
            }
        }
    };
    pub fn directory(self: *const FileSystem, descriptor: File) Error!DirectoryIterator {
        if (!descriptor.directory) return error.NotDirectory;
        return .{ .fs = self, .parent = descriptor };
    }
    pub fn open(self: *const FileSystem, path: []const u8) Error!File {
        try @import("path.zig").validate(path);
        var current = try self.file(5);
        if (path.len == 1) return current;
        var parts = std.mem.splitScalar(u8, path[1..], '/');
        while (parts.next()) |part| {
            var iterator = try self.directory(current);
            var found: ?u64 = null;
            while (try iterator.next()) |entry| {
                if (std.ascii.eqlIgnoreCase(entry.name, part)) {
                    found = entry.number;
                    break;
                }
            }
            current = try self.file(found orelse return error.NotFound);
        }
        return current;
    }
    pub fn read(self: *const FileSystem, path: []const u8) Error![]const u8 {
        return self.view(try self.open(path));
    }
    pub fn list(self: *const FileSystem, path: []const u8, writer: anytype) !void {
        var iterator = try self.directory(try self.open(path));
        while (try iterator.next()) |entry| {
            try writer.write(entry.name);
            try writer.write(if (entry.directory) "/\r\n" else "\r\n");
        }
    }
};
fn resident(attribute: []const u8) Error![]const u8 {
    if (attribute[8] != 0) return error.UnsupportedFeature;
    const size = le(u32, attribute, 16);
    const offset = le(u16, attribute, 20);
    if (offset < 24 or offset > attribute.len or size > attribute.len - offset) return error.InvalidFilesystem;
    return attribute[offset..][0..size];
}
fn variable(bytes: []const u8) u64 {
    var value: u64 = 0;
    for (bytes, 0..) |byte, index| value |= @as(u64, byte) << @as(u6, @intCast(index * 8));
    return value;
}
fn le(comptime T: type, bytes: []const u8, offset: usize) T {
    return std.mem.readInt(T, bytes[offset..][0..@sizeOf(T)], .little);
}
