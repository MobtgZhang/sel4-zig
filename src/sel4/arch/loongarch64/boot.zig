//! QEMU direct ELF boot supplies a synthetic EFI system table in a2.
//! Only the bounded low-memory configuration table and its DTB are consumed.
const std = @import("std");
const handoff = @import("../../boot/handoff.zig");
fn low(address: u64, length: usize) ![]const u8 {
    if (address == 0 or address >= 0x100000 or length > 0x100000 - address) return error.InvalidBootData;
    return @as([*]const u8, @ptrFromInt(0x9000000000000000 | address))[0..length];
}
pub fn fill(h: *handoff.BootHandoff, system_table: u64) !void {
    const header = try low(system_table, 120);
    if (std.mem.readInt(u64, header[0..8], .little) != 0x5453595320494249) return error.InvalidBootData;
    const count = std.mem.readInt(u64, header[104..112], .little);
    const table_address = std.mem.readInt(u64, header[112..120], .little);
    if (count > 64) return error.InvalidBootData;
    const tables = try low(table_address, @intCast(count * 24));
    const dt_guid = [_]u8{ 0xd5, 0x21, 0xb6, 0xb1, 0x9c, 0xf1, 0xa5, 0x41, 0x83, 0x0b, 0xd9, 0x15, 0x2c, 0x69, 0xaa, 0xe0 };
    for (0..@intCast(count)) |i| {
        const entry = tables[i * 24 ..][0..24];
        if (!std.mem.eql(u8, entry[0..16], &dt_guid)) continue;
        const physical = std.mem.readInt(u64, entry[16..24], .little);
        if (physical == 0 or physical >= 0x10000000) return error.InvalidBootData;
        try @import("../../boot/fdt.zig").fillFromFdt(h, 0x9000000000000000 | physical);
        // The generic inventory records physical addresses, never DMW aliases.
        h.mb2_phys = physical;
        for (h.reserved[0..h.reserved_count]) |*region| {
            region.start &= 0x0000ffffffffffff;
            region.end &= 0x0000ffffffffffff;
        }
        // Linux EFI initrd media GUID (QEMU's synthetic direct-boot table).
        const initrd_guid = [_]u8{ 0x27, 0xe4, 0x68, 0x55, 0xfc, 0x68, 0x3d, 0x4f, 0xac, 0x74, 0xca, 0x55, 0x52, 0x31, 0xcc, 0x68 };
        for (0..@intCast(count)) |j| {
            const candidate = tables[j * 24 ..][0..24];
            if (!std.mem.eql(u8, candidate[0..16], &initrd_guid)) continue;
            const initrd = try low(std.mem.readInt(u64, candidate[16..24], .little), 16);
            h.ramdisk_address = std.mem.readInt(u64, initrd[0..8], .little);
            h.ramdisk_size = std.mem.readInt(u64, initrd[8..16], .little);
            try handoff.reserve(h, h.ramdisk_address, h.ramdisk_size);
        }
        return;
    }
    return error.NoDeviceTree;
}
