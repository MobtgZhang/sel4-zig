//! Bounded flattened-device-tree memory inventory (DT specification v17).
//! Only root memory nodes and untranslated /reserved-memory regions are accepted.
const std = @import("std");
const handoff = @import("handoff.zig");
const memory = @import("../kernel/boot_mem.zig");
pub const Error = handoff.Error || error{ UnsupportedTree, OutOfRegions };
fn be(comptime T: type, bytes: []const u8, offset: usize) Error!T {
    if (offset > bytes.len or @sizeOf(T) > bytes.len - offset) return error.InvalidBootData;
    return std.mem.readInt(T, bytes[offset..][0..@sizeOf(T)], .big);
}
fn bounded(bytes: []const u8, offset: usize, length: usize) Error![]const u8 {
    if (offset > bytes.len or length > bytes.len - offset) return error.InvalidBootData;
    return bytes[offset..][0..length];
}
fn cstring(bytes: []const u8, offset: usize) Error![]const u8 {
    const rest = try bounded(bytes, offset, bytes.len -| offset);
    const end = std.mem.indexOfScalar(u8, rest, 0) orelse return error.InvalidBootData;
    return rest[0..end];
}
const Node = struct {
    address_cells: u32 = 2,
    size_cells: u32 = 1,
    parent_address_cells: u32 = 2,
    parent_size_cells: u32 = 1,
    memory_node: bool = false,
    chosen: bool = false,
    cpu_bus: bool = false,
    cpu_node: bool = false,
    reservation_bus: bool = false,
    reservation: bool = false,
    enabled: bool = true,
    reg: ?[]const u8 = null,
};
fn cells(bytes: []const u8, count: u32) Error!u64 {
    if (count == 0 or count > 2) return error.UnsupportedTree;
    var result: u64 = 0;
    for (0..count) |i| result = (result << 32) | try be(u32, bytes, i * 4);
    return result;
}
fn appendRegs(set: *memory.RegionSet, node: Node) Error!void {
    const reg = node.reg orelse return error.InvalidBootData;
    if (node.parent_address_cells == 0 or node.parent_address_cells > 2 or node.parent_size_cells == 0 or node.parent_size_cells > 2) return error.UnsupportedTree;
    const address_bytes: usize = node.parent_address_cells * 4;
    const stride: usize = address_bytes + node.parent_size_cells * 4;
    if (reg.len % stride != 0) return error.InvalidBootData;
    var offset: usize = 0;
    while (offset < reg.len) : (offset += stride) {
        const address = try cells(reg[offset..], node.parent_address_cells);
        const length = try cells(reg[offset + address_bytes ..], node.parent_size_cells);
        const end = std.math.add(u64, address, length) catch return error.InvalidBootData;
        if (length != 0) try set.add(.{ .start = address, .end = end });
    }
}

pub fn parse(bytes: []const u8, physical: u64) Error!handoff.BootHandoff {
    if (try be(u32, bytes, 0) != 0xd00dfeed) return error.InvalidBootData;
    const total = try be(u32, bytes, 4);
    if (total < 40 or total > bytes.len) return error.InvalidBootData;
    const blob = bytes[0..total];
    if (try be(u32, blob, 20) < 17 or try be(u32, blob, 24) > 17) return error.UnsupportedTree;
    const structure = try bounded(blob, try be(u32, blob, 8), try be(u32, blob, 36));
    const strings = try bounded(blob, try be(u32, blob, 12), try be(u32, blob, 32));
    var ram: memory.RegionSet = .{};
    var reserved: memory.RegionSet = .{};
    var topology: handoff.BootHandoff = .{};
    var reserve_offset: usize = try be(u32, blob, 16);
    if (reserve_offset % 8 != 0 or reserve_offset < 40) return error.InvalidBootData;
    while (true) : (reserve_offset += 16) {
        const address = try be(u64, blob, reserve_offset);
        const size = try be(u64, blob, reserve_offset + 8);
        if (address == 0 and size == 0) break;
        const end = std.math.add(u64, address, size) catch return error.InvalidBootData;
        if (size != 0) try reserved.add(.{ .start = address, .end = end });
    }
    var nodes: [32]Node = undefined;
    var depth: usize = 0;
    var offset: usize = 0;
    var seen_root = false;
    var initrd_start: ?u64 = null;
    var initrd_end: ?u64 = null;
    while (offset < structure.len) {
        const token = try be(u32, structure, offset);
        offset += 4;
        switch (token) {
            1 => {
                if (depth == nodes.len or (depth == 0 and seen_root)) return error.InvalidBootData;
                const name = try cstring(structure, offset);
                offset = std.mem.alignForward(usize, offset + name.len + 1, 4);
                if (offset > structure.len) return error.InvalidBootData;
                var node: Node = .{};
                if (depth == 0) {
                    if (name.len != 0) return error.InvalidBootData;
                    seen_root = true;
                } else {
                    node.parent_address_cells = nodes[depth - 1].address_cells;
                    node.parent_size_cells = nodes[depth - 1].size_cells;
                    node.enabled = nodes[depth - 1].enabled;
                    node.memory_node = std.mem.eql(u8, name, "memory") or std.mem.startsWith(u8, name, "memory@");
                    node.chosen = depth == 1 and std.mem.eql(u8, name, "chosen");
                    node.cpu_bus = depth == 1 and std.mem.eql(u8, name, "cpus");
                    node.cpu_node = nodes[depth - 1].cpu_bus and std.mem.startsWith(u8, name, "cpu@");
                    if (node.memory_node and depth != 1) return error.UnsupportedTree;
                    node.reservation_bus = depth == 1 and std.mem.eql(u8, name, "reserved-memory");
                    node.reservation = nodes[depth - 1].reservation_bus;
                }
                nodes[depth] = node;
                depth += 1;
            },
            2 => {
                if (depth == 0) return error.InvalidBootData;
                depth -= 1;
                const node = nodes[depth];
                if (node.enabled and node.memory_node) try appendRegs(&ram, node);
                if (node.enabled and node.reservation and node.reg != null) try appendRegs(&reserved, node);
                if (node.enabled and node.cpu_node) {
                    const reg = node.reg orelse return error.InvalidBootData;
                    if (reg.len != node.parent_address_cells * 4) return error.InvalidBootData;
                    try handoff.addCpu(&topology, try cells(reg, node.parent_address_cells));
                }
            },
            3 => {
                if (depth == 0) return error.InvalidBootData;
                const length = try be(u32, structure, offset);
                const name = try cstring(strings, try be(u32, structure, offset + 4));
                offset += 8;
                const data = try bounded(structure, offset, length);
                offset = std.mem.alignForward(usize, offset + length, 4);
                if (offset > structure.len) return error.InvalidBootData;
                const node = &nodes[depth - 1];
                if (std.mem.eql(u8, name, "#address-cells")) {
                    if (length != 4) return error.InvalidBootData;
                    node.address_cells = try be(u32, data, 0);
                } else if (std.mem.eql(u8, name, "#size-cells")) {
                    if (length != 4) return error.InvalidBootData;
                    node.size_cells = try be(u32, data, 0);
                } else if (node.chosen and std.mem.eql(u8, name, "linux,initrd-start")) {
                    if (length != 4 and length != 8) return error.InvalidBootData;
                    initrd_start = try cells(data, length / 4);
                } else if (node.chosen and std.mem.eql(u8, name, "linux,initrd-end")) {
                    if (length != 4 and length != 8) return error.InvalidBootData;
                    initrd_end = try cells(data, length / 4);
                } else if (std.mem.eql(u8, name, "reg")) {
                    node.reg = data;
                } else if (std.mem.eql(u8, name, "status")) {
                    const status = try cstring(data, 0);
                    node.enabled = node.enabled and (std.mem.eql(u8, status, "okay") or std.mem.eql(u8, status, "ok"));
                } else if (node.reservation_bus and std.mem.eql(u8, name, "ranges") and length != 0) return error.UnsupportedTree;
            },
            4 => {},
            9 => {
                if (!seen_root or depth != 0 or ram.count == 0) return error.InvalidBootData;
                for (reserved.regions[0..reserved.count]) |region| try ram.subtract(region);
                var result = handoff.BootHandoff{ .flags = handoff.flag_fdt, .mb2_phys = physical };
                if (initrd_start != null or initrd_end != null) {
                    const start = initrd_start orelse return error.InvalidBootData;
                    const end = initrd_end orelse return error.InvalidBootData;
                    if (end <= start) return error.InvalidBootData;
                    result.ramdisk_address = start;
                    result.ramdisk_size = end - start;
                    try handoff.reserve(&result, start, end - start);
                }
                result.cpu_count = topology.cpu_count;
                result.cpu_ids = topology.cpu_ids;
                try handoff.reserve(&result, physical, total);
                for (ram.regions[0..ram.count]) |region| try handoff.append(&result, region.start, region.end - region.start);
                if (result.region_count == 0) return error.NoUsableMemory;
                return result;
            },
            else => return error.InvalidBootData,
        }
    }
    return error.InvalidBootData;
}

/// Firmware must map the header and the total-size extent before entering Zig.
pub fn fillFromFdt(h: *handoff.BootHandoff, physical: u64) Error!void {
    if (physical == 0 or physical % 8 != 0) return error.InvalidBootData;
    const pointer: [*]const u8 = @ptrFromInt(physical);
    const total = try be(u32, pointer[0..40], 4);
    if (total < 40 or total > 16 * 1024 * 1024 or physical > std.math.maxInt(u64) - @as(u64, total)) return error.InvalidBootData;
    h.* = try parse(pointer[0..total], physical);
}

test "FDT rejects truncated and malformed headers without inventing memory" {
    var bytes: [40]u8 = @splat(0);
    try std.testing.expectError(error.InvalidBootData, parse(&bytes, 0));
    std.mem.writeInt(u32, bytes[0..4], 0xd00dfeed, .big);
    std.mem.writeInt(u32, bytes[4..8], 80, .big);
    try std.testing.expectError(error.InvalidBootData, parse(&bytes, 0));
}

test "FDT reads v17 header offsets and excludes firmware reservations" {
    const Builder = struct {
        bytes: [512]u8 = @splat(0),
        offset: usize = 72,
        fn word(self: *@This(), value: u32) void {
            std.mem.writeInt(u32, self.bytes[self.offset..][0..4], value, .big);
            self.offset += 4;
        }
        fn node(self: *@This(), name: []const u8) void {
            self.word(1);
            @memcpy(self.bytes[self.offset..][0..name.len], name);
            self.offset = std.mem.alignForward(usize, self.offset + name.len + 1, 4);
        }
        fn property(self: *@This(), name: u32, value: []const u8) void {
            self.word(3);
            self.word(@intCast(value.len));
            self.word(name);
            @memcpy(self.bytes[self.offset..][0..value.len], value);
            self.offset = std.mem.alignForward(usize, self.offset + value.len, 4);
        }
    };
    var builder: Builder = .{};
    builder.node("");
    builder.property(0, &.{ 0, 0, 0, 2 });
    builder.property(15, &.{ 0, 0, 0, 2 });
    builder.node("memory@40000000");
    builder.property(27, &.{ 0, 0, 0, 0, 0x40, 0, 0, 0, 0, 0, 0, 0, 0x10, 0, 0, 0 });
    builder.word(2);
    builder.word(2);
    builder.word(9);
    const strings = "#address-cells\x00#size-cells\x00reg\x00";
    const strings_offset = builder.offset;
    @memcpy(builder.bytes[strings_offset..][0..strings.len], strings);
    const total = strings_offset + strings.len;
    const header = [_]u32{ 0xd00dfeed, @intCast(total), 72, @intCast(strings_offset), 40, 17, 16, 0, strings.len, @intCast(strings_offset - 72) };
    for (header, 0..) |value, i| std.mem.writeInt(u32, builder.bytes[i * 4 ..][0..4], value, .big);
    std.mem.writeInt(u64, builder.bytes[40..48], 0x41000000, .big);
    std.mem.writeInt(u64, builder.bytes[48..56], 0x1000, .big);
    const result = try parse(builder.bytes[0..total], 0x48000000);
    try std.testing.expectEqual(@as(u32, 2), result.region_count);
    try std.testing.expectEqual(@as(u64, 0x41000000), result.regions[0].end);
    try std.testing.expectEqual(@as(u64, 0x41001000), result.regions[1].start);
    try std.testing.expectEqual(@as(u64, 0x50000000), result.regions[1].end);
    // A broken strings offset must fail without returning partial memory inventory.
    std.mem.writeInt(u32, builder.bytes[12..16], 0xfffffff0, .big);
    try std.testing.expectError(error.InvalidBootData, parse(builder.bytes[0..total], 0));
}
