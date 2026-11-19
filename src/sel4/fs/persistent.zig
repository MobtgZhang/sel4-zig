//! Bounded durable file store over 512-byte sectors. Each slot has two records.
//! Data is flushed before its checksummed commit sector; recovery chooses the
//! newest complete record and falls back after interrupted writes or corruption.
const std = @import("std");
pub const slots = 32;
pub const max_data = 3584;
const magic = "ZIGFS001";
const volume_magic = "ZIGVOL01";
pub const required_sectors = 513;
const Record = struct { generation: u64, length: u16, deleted: bool, name: [64]u8, name_length: u8, bank: u1 };
pub fn Store(comptime Device: type) type {
    return struct {
        const Self = @This();
        device: Device,
        records: [slots]?Record = @splat(null),
        pub fn mount(device: Device) !Self {
            var self: Self = .{ .device = device };
            var super: [512]u8 = undefined;
            try self.device.read(0, &super);
            if (!std.mem.eql(u8, super[0..8], volume_magic) or std.mem.readInt(u32, super[8..12], .little) != required_sectors or std.hash.Crc32.hash(super[0..508]) != std.mem.readInt(u32, super[508..512], .little)) return error.InvalidVolume;
            for (0..slots) |slot| {
                for (0..2) |bank| {
                    const record = self.load(slot, @intCast(bank)) catch |err| {
                        if (err == error.InvalidRecord or err == error.InvalidPath) continue;
                        return err;
                    };
                    if (self.records[slot] == null or record.generation > self.records[slot].?.generation) self.records[slot] = record;
                }
            }
            return self;
        }
        fn load(self: *Self, slot: usize, bank: u1) !Record {
            var header: [512]u8 = undefined;
            try self.device.read(1 + slot * 16 + @as(u64, bank) * 8, &header);
            if (!std.mem.eql(u8, header[0..8], magic) or std.hash.Crc32.hash(header[0..508]) != std.mem.readInt(u32, header[508..512], .little)) return error.InvalidRecord;
            const length = std.mem.readInt(u16, header[16..18], .little);
            if (length > max_data or header[18] > 1 or header[19] == 0 or header[19] > 64) return error.InvalidRecord;
            const record: Record = .{ .generation = std.mem.readInt(u64, header[8..16], .little), .length = length, .deleted = header[18] == 1, .name = header[20..84].*, .name_length = header[19], .bank = bank };
            try validName(record.name[0..record.name_length]);
            var bytes: [max_data]u8 = undefined;
            try self.readBody(slot, record, &bytes);
            if (std.hash.Crc32.hash(bytes[0..length]) != std.mem.readInt(u32, header[84..88], .little)) return error.InvalidRecord;
            return record;
        }
        fn readBody(self: *Self, slot: usize, record: Record, bytes: *[max_data]u8) !void {
            var sector: [512]u8 = undefined;
            var offset: usize = 0;
            while (offset < record.length) : (offset += 512) {
                try self.device.read(2 + slot * 16 + @as(u64, record.bank) * 8 + offset / 512, &sector);
                const count = @min(512, record.length - offset);
                @memcpy(bytes[offset..][0..count], sector[0..count]);
            }
        }
        fn find(self: *Self, name: []const u8) ?usize {
            for (self.records, 0..) |record, index| if (record) |r| {
                if (std.mem.eql(u8, r.name[0..r.name_length], name)) return index;
            };
            return null;
        }
        pub fn read(self: *Self, name: []const u8, bytes: *[max_data]u8) ![]const u8 {
            try validName(name);
            const slot = self.find(name) orelse return error.NotFound;
            const record = self.records[slot].?;
            if (record.deleted) return error.NotFound;
            try self.readBody(slot, record, bytes);
            return bytes[0..record.length];
        }
        pub fn write(self: *Self, name: []const u8, bytes: []const u8) !void {
            try self.commit(name, bytes, false);
        }
        pub fn remove(self: *Self, name: []const u8) !void {
            const slot = self.find(name) orelse return error.NotFound;
            if (self.records[slot].?.deleted) return error.NotFound;
            try self.commit(name, "", true);
        }
        fn commit(self: *Self, name: []const u8, bytes: []const u8, deleted: bool) !void {
            try validName(name);
            if (bytes.len > max_data) return error.FileTooLarge;
            const slot = self.find(name) orelse blk: {
                for (self.records, 0..) |record, index| if (record == null or record.?.deleted) break :blk index;
                return error.DirectoryFull;
            };
            const old = self.records[slot];
            const generation = if (old) |r| try std.math.add(u64, r.generation, 1) else 1;
            const bank: u1 = if (old) |r| r.bank ^ 1 else 0;
            var sector: [512]u8 = @splat(0);
            var offset: usize = 0;
            while (offset < bytes.len) : (offset += 512) {
                @memset(&sector, 0);
                const count = @min(512, bytes.len - offset);
                @memcpy(sector[0..count], bytes[offset..][0..count]);
                try self.device.write(2 + slot * 16 + @as(u64, bank) * 8 + offset / 512, &sector);
            }
            try self.device.flush();
            @memset(&sector, 0);
            @memcpy(sector[0..8], magic);
            std.mem.writeInt(u64, sector[8..16], generation, .little);
            std.mem.writeInt(u16, sector[16..18], @intCast(bytes.len), .little);
            sector[18] = @intFromBool(deleted);
            sector[19] = @intCast(name.len);
            @memcpy(sector[20..][0..name.len], name);
            std.mem.writeInt(u32, sector[84..88], std.hash.Crc32.hash(bytes), .little);
            std.mem.writeInt(u32, sector[508..512], std.hash.Crc32.hash(sector[0..508]), .little);
            try self.device.write(1 + slot * 16 + @as(u64, bank) * 8, &sector);
            try self.device.flush();
            self.records[slot] = .{ .generation = generation, .length = @intCast(bytes.len), .deleted = deleted, .name = sector[20..84].*, .name_length = @intCast(name.len), .bank = bank };
        }
        pub fn list(self: *Self, writer: anytype) !void {
            for (self.records) |record| if (record) |r| {
                if (!r.deleted) {
                    try writer.write(r.name[0..r.name_length]);
                    try writer.write("\r\n");
                }
            };
        }
    };
}
fn validName(name: []const u8) !void {
    if (name.len == 0 or name.len > 64 or !std.unicode.utf8ValidateSlice(name) or std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) return error.InvalidPath;
    for (name) |byte| if (byte == '/' or byte == 0 or byte < 32) return error.InvalidPath;
}
const MemoryDisk = struct {
    sectors: *[513][512]u8,
    budget: *usize,
    fn read(self: MemoryDisk, sector: u64, bytes: *[512]u8) !void {
        bytes.* = self.sectors[@intCast(sector)];
    }
    fn write(self: MemoryDisk, sector: u64, bytes: *const [512]u8) !void {
        if (self.budget.* == 0) return error.PowerLost;
        self.budget.* -= 1;
        self.sectors[@intCast(sector)] = bytes.*;
    }
    fn flush(_: MemoryDisk) !void {}
};
test "durable records recover old or new complete content after every interrupted sector write" {
    var disk: [513][512]u8 = @splat(@splat(0));
    var budget: usize = 10000;
    const device: MemoryDisk = .{ .sectors = &disk, .budget = &budget };
    @memcpy(disk[0][0..8], volume_magic);
    std.mem.writeInt(u32, disk[0][8..12], required_sectors, .little);
    std.mem.writeInt(u32, disk[0][508..512], std.hash.Crc32.hash(disk[0][0..508]), .little);
    var store = try Store(MemoryDisk).mount(device);
    try store.write("test", "old");
    const original = disk;
    const replacement: [1200]u8 = @splat('n');
    for (0..5) |cut| {
        disk = original;
        budget = cut;
        store = try Store(MemoryDisk).mount(device);
        store.write("test", &replacement) catch {};
        var recovered = try Store(MemoryDisk).mount(device);
        var bytes: [max_data]u8 = undefined;
        const found = try recovered.read("test", &bytes);
        try std.testing.expect(std.mem.eql(u8, found, "old") or std.mem.eql(u8, found, &replacement));
    }
    budget = 10000;
    try store.remove("test");
    store = try Store(MemoryDisk).mount(device);
    var bytes: [max_data]u8 = undefined;
    try std.testing.expectError(error.NotFound, store.read("test", &bytes));
}

test "mount rejects foreign disks without modifying them" {
    var disk: [513][512]u8 = @splat(@splat(0xa5));
    var budget: usize = 100;
    const device: MemoryDisk = .{ .sectors = &disk, .budget = &budget };
    try std.testing.expectError(error.InvalidVolume, Store(MemoryDisk).mount(device));
    try std.testing.expectEqual(@as(usize, 100), budget);
    try std.testing.expectEqual(@as(u8, 0xa5), disk[0][0]);
}

test "mount propagates device failure while scanning record headers" {
    const FailingDisk = struct {
        fn read(_: @This(), sector: u64, bytes: *[512]u8) !void {
            if (sector != 0) return error.DiskUnavailable;
            @memset(bytes, 0);
            @memcpy(bytes[0..8], volume_magic);
            std.mem.writeInt(u32, bytes[8..12], required_sectors, .little);
            std.mem.writeInt(u32, bytes[508..512], std.hash.Crc32.hash(bytes[0..508]), .little);
        }
    };
    try std.testing.expectError(error.DiskUnavailable, Store(FailingDisk).mount(.{}));
}

test "corrupt newest body falls back to the previous committed record" {
    var disk: [513][512]u8 = @splat(@splat(0));
    @memcpy(disk[0][0..8], volume_magic);
    std.mem.writeInt(u32, disk[0][8..12], required_sectors, .little);
    std.mem.writeInt(u32, disk[0][508..512], std.hash.Crc32.hash(disk[0][0..508]), .little);
    var budget: usize = 100;
    const device: MemoryDisk = .{ .sectors = &disk, .budget = &budget };
    var store = try Store(MemoryDisk).mount(device);
    try store.write("data", "previous");
    try store.write("data", "newest");
    disk[10][0] ^= 1;
    store = try Store(MemoryDisk).mount(device);
    var bytes: [max_data]u8 = undefined;
    try std.testing.expectEqualStrings("previous", try store.read("data", &bytes));
    try store.remove("data");
    store = try Store(MemoryDisk).mount(device);
    try std.testing.expectError(error.NotFound, store.read("data", &bytes));
}
