//! Bounded ACPI MADT parsing for x86, Arm, RISC-V and LoongArch CPU inventory.
const std = @import("std");
const handoff = @import("handoff.zig");
fn checksum(bytes: []const u8) bool {
    var sum: u8 = 0;
    for (bytes) |byte| sum +%= byte;
    return sum == 0;
}
pub fn parseMadt(h: *handoff.BootHandoff, bytes: []const u8) !void {
    if (bytes.len < 44 or !std.mem.eql(u8, bytes[0..4], "APIC")) return error.InvalidAcpi;
    const length = std.mem.readInt(u32, bytes[4..8], .little);
    if (length < 44 or length > bytes.len or !checksum(bytes[0..length])) return error.InvalidAcpi;
    var topology: handoff.BootHandoff = .{};
    var offset: usize = 44;
    while (offset < length) {
        if (length - offset < 2) return error.InvalidAcpi;
        const kind = bytes[offset];
        const size = bytes[offset + 1];
        if (size < 2 or size > length - offset) return error.InvalidAcpi;
        const entry = bytes[offset..][0..size];
        if (kind == 0) {
            if (size < 8) return error.InvalidAcpi;
            if (std.mem.readInt(u32, entry[4..8], .little) & 1 != 0) try handoff.addCpu(&topology, entry[3]);
        } else if (kind == 9) {
            if (size < 16) return error.InvalidAcpi;
            if (std.mem.readInt(u32, entry[8..12], .little) & 1 != 0) try handoff.addCpu(&topology, std.mem.readInt(u32, entry[4..8], .little));
        } else if (kind == 11) {
            // GICC hardware identity is MPIDR, not the ACPI processor UID.
            if (size < 76) return error.InvalidAcpi;
            if (std.mem.readInt(u32, entry[12..16], .little) & 1 != 0)
                try handoff.addCpu(&topology, std.mem.readInt(u64, entry[68..76], .little) & 0xff00ffffff);
        } else if (kind == 17) {
            // Core PIC structures are packed; core_id begins at byte seven.
            if (size < 15) return error.InvalidAcpi;
            if (std.mem.readInt(u32, entry[11..15], .little) & 1 != 0)
                try handoff.addCpu(&topology, std.mem.readInt(u32, entry[7..11], .little));
        } else if (kind == 24) {
            if (size < 36) return error.InvalidAcpi;
            if (std.mem.readInt(u32, entry[4..8], .little) & 1 != 0)
                try handoff.addCpu(&topology, std.mem.readInt(u64, entry[8..16], .little));
        }
        offset += size;
    }
    h.cpu_count = topology.cpu_count;
    h.cpu_ids = topology.cpu_ids;
}
fn table(address: u64) ![]const u8 {
    if (address < 4096 or address > 0x1_0000_0000 - 36) return error.InvalidAcpi;
    const pointer: [*]const u8 = @ptrFromInt(address);
    const length = std.mem.readInt(u32, pointer[4..8], .little);
    if (length < 36 or length > 65536 or length > 0x1_0000_0000 - address) return error.InvalidAcpi;
    const result = pointer[0..length];
    if (!checksum(result)) return error.InvalidAcpi;
    return result;
}
/// The caller must supply mapped firmware memory for the RSDP and ACPI tables.
pub fn discover(h: *handoff.BootHandoff, rsdp: [*]const u8) !void {
    if (!std.mem.eql(u8, rsdp[0..8], "RSD PTR ") or !checksum(rsdp[0..20])) return error.InvalidAcpi;
    const extended = rsdp[15] >= 2;
    if (extended and (std.mem.readInt(u32, rsdp[20..24], .little) != 36 or !checksum(rsdp[0..36]))) return error.InvalidAcpi;
    const root = try table(if (extended) std.mem.readInt(u64, rsdp[24..32], .little) else std.mem.readInt(u32, rsdp[16..20], .little));
    if (!std.mem.eql(u8, root[0..4], if (extended) "XSDT" else "RSDT")) return error.InvalidAcpi;
    const stride: usize = if (extended) 8 else 4;
    if ((root.len - 36) % stride != 0) return error.InvalidAcpi;
    var offset: usize = 36;
    while (offset < root.len) : (offset += stride) {
        const address = if (extended) std.mem.readInt(u64, root[offset..][0..8], .little) else std.mem.readInt(u32, root[offset..][0..4], .little);
        const child = try table(address);
        if (std.mem.eql(u8, child[0..4], "APIC")) {
            try parseMadt(h, child);
            return;
        }
    }
    return error.NoMadt;
}
test "MADT rejects malformed records and preserves CPU inventory on failure" {
    var bytes: [60]u8 = @splat(0);
    @memcpy(bytes[0..4], "APIC");
    std.mem.writeInt(u32, bytes[4..8], bytes.len, .little);
    bytes[45] = 8;
    bytes[47] = 7;
    bytes[48] = 1;
    bytes[53] = 8;
    bytes[55] = 42;
    bytes[56] = 1;
    var sum: u8 = 0;
    for (bytes) |byte| sum +%= byte;
    bytes[9] -%= sum;
    var h: handoff.BootHandoff = .{};
    try parseMadt(&h, &bytes);
    try std.testing.expectEqual(@as(u32, 2), h.cpu_count);
    bytes[45] = 0;
    try std.testing.expectError(error.InvalidAcpi, parseMadt(&h, &bytes));
    try std.testing.expectEqual(@as(u32, 2), h.cpu_count);
}

test "MADT uses architectural identities and excludes disabled non-x86 processors" {
    inline for (.{ .{ @as(u8, 11), 76, 12, 68 }, .{ @as(u8, 17), 15, 11, 7 }, .{ @as(u8, 24), 36, 4, 8 } }) |layout| {
        const kind, const size, const flags_offset, const identity_offset = layout;
        var bytes: [44 + size * 2]u8 = @splat(0);
        @memcpy(bytes[0..4], "APIC");
        std.mem.writeInt(u32, bytes[4..8], bytes.len, .little);
        for (0..2) |index| {
            const base = 44 + index * size;
            bytes[base] = kind;
            bytes[base + 1] = size;
            std.mem.writeInt(u32, bytes[base + flags_offset ..][0..4], if (index == 0) 1 else 0, .little);
            if (kind == 17) {
                std.mem.writeInt(u32, bytes[base + identity_offset ..][0..4], 42, .little);
            } else {
                std.mem.writeInt(u64, bytes[base + identity_offset ..][0..8], 42, .little);
            }
        }
        var sum: u8 = 0;
        for (bytes) |byte| sum +%= byte;
        bytes[9] -%= sum;
        var h: handoff.BootHandoff = .{};
        try parseMadt(&h, &bytes);
        try std.testing.expectEqual(@as(u32, 1), h.cpu_count);
        try std.testing.expectEqual(@as(u64, 42), h.cpu_ids[0]);
    }
}
