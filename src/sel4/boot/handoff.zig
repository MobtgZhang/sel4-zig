//! Stable firmware-to-kernel memory inventory. All regions are half-open.
//! Malformed firmware data is rejected; it must never manufacture usable RAM.
const std = @import("std");
pub const PhysRegion = @import("../mm/phys_region.zig").PhysRegion;
pub const HandoffPhysRegion = extern struct { start: u64, end: u64 };
pub const magic: u64 = std.mem.readInt(u64, "L4ZHAND1", .little);
pub const flag_multiboot_mmap: u32 = 1;
pub const flag_uefi_handoff: u32 = 2;
pub const flag_fdt: u32 = 4;
pub const flag_pvh: u32 = 8;
pub const flag_recovery: u32 = 16;
pub const BootHandoff = extern struct {
    magic: u64 = magic,
    version: u32 = 3,
    flags: u32 = 0,
    /// Physical address of the originating boot structure, or zero for UEFI.
    mb2_phys: u64 = 0,
    region_count: u32 = 0,
    _pad: u32 = 0,
    regions: [64]HandoffPhysRegion = @splat(.{ .start = 0, .end = 0 }),
    framebuffer: @import("../drivers/framebuffer.zig").Descriptor = .{},
    reserved_count: u32 = 0,
    cpu_count: u32 = 0,
    reserved: [32]HandoffPhysRegion = @splat(.{ .start = 0, .end = 0 }),
    cpu_ids: [64]u64 = @splat(0),
    boot_cpu_id: u64 = 0,
    ramdisk_address: u64 = 0,
    ramdisk_size: u64 = 0,
};
pub const Error = error{ InvalidBootData, TooManyRegions, NoUsableMemory };

pub fn reserve(h: *BootHandoff, start: u64, length: u64) Error!void {
    if (length == 0) return;
    const end = std.math.add(u64, start, length) catch return error.InvalidBootData;
    if (h.reserved_count == h.reserved.len) return error.TooManyRegions;
    h.reserved[h.reserved_count] = .{ .start = start, .end = end };
    h.reserved_count += 1;
}
pub fn addCpu(h: *BootHandoff, id: u64) Error!void {
    for (h.cpu_ids[0..h.cpu_count]) |old| if (id == old) return error.InvalidBootData;
    if (h.cpu_count == h.cpu_ids.len) return error.TooManyRegions;
    h.cpu_ids[h.cpu_count] = id;
    h.cpu_count += 1;
}

pub fn append(h: *BootHandoff, start: u64, length: u64) Error!void {
    if (length == 0) return;
    const end = std.math.add(u64, start, length) catch return error.InvalidBootData;
    if (h.region_count >= h.regions.len) return error.TooManyRegions;
    h.regions[h.region_count] = .{ .start = start, .end = end };
    h.region_count += 1;
}
fn read(comptime T: type, bytes: []const u8, offset: usize) Error!T {
    if (offset > bytes.len or @sizeOf(T) > bytes.len - offset) return error.InvalidBootData;
    return std.mem.readInt(T, bytes[offset..][0..@sizeOf(T)], .little);
}

/// Parse a bounded Multiboot2 information block. The caller owns its mapping.
pub fn parseMultiboot2(bytes: []const u8, physical: u64) Error!BootHandoff {
    const total = try read(u32, bytes, 0);
    if (total < 16 or total > bytes.len or total % 8 != 0) return error.InvalidBootData;
    const block = bytes[0..total];
    var h = BootHandoff{ .flags = flag_multiboot_mmap, .mb2_phys = physical };
    try reserve(&h, physical, total);
    var offset: usize = 8;
    while (offset < block.len) {
        const kind = try read(u32, block, offset);
        const size = try read(u32, block, offset + 4);
        if (size < 8 or size > block.len - offset) return error.InvalidBootData;
        if (kind == 0) {
            if (size != 8 or offset + 8 != total) return error.InvalidBootData;
            if (h.region_count == 0) return error.NoUsableMemory;
            return h;
        }
        if (kind == 6) {
            if (size < 16) return error.InvalidBootData;
            const stride = try read(u32, block, offset + 8);
            if (stride < 24 or (size - 16) % stride != 0 or try read(u32, block, offset + 12) != 0) return error.InvalidBootData;
            var entry = offset + 16;
            while (entry < offset + size) : (entry += stride) {
                if (try read(u32, block, entry + 16) == 1) try append(&h, try read(u64, block, entry), try read(u64, block, entry + 8));
            }
        }
        if (kind == 14 or kind == 15) {
            const rsdp = block[offset + 8 .. offset + size];
            if (rsdp.len < 20 or (kind == 15 and rsdp.len < 36)) return error.InvalidBootData;
            @import("acpi.zig").discover(&h, rsdp.ptr) catch |err| {
                if (err != error.NoMadt) return error.InvalidBootData;
            };
        }
        if (kind == 3) {
            if (size < 16) return error.InvalidBootData;
            const start = try read(u32, block, offset + 8);
            const end = try read(u32, block, offset + 12);
            if (end < start) return error.InvalidBootData;
            try reserve(&h, start, end - start);
            if (h.ramdisk_size == 0) {
                h.ramdisk_address = start;
                h.ramdisk_size = end - start;
            }
        }
        offset += std.mem.alignForward(usize, size, 8);
    }
    return error.InvalidBootData;
}

/// Bootstrap x86 page tables cover only the first 4 GiB.
fn lowMemory(physical: u64, length: u64) Error![]const u8 {
    if (physical == 0 or physical >= 0x1_0000_0000 or length > 0x1_0000_0000 - physical) return error.InvalidBootData;
    return @as([*]const u8, @ptrFromInt(physical))[0..@intCast(length)];
}
pub fn fillFromMultiboot2(h: *BootHandoff, physical: u64) Error!void {
    const prefix = try lowMemory(physical, 8);
    const length = try read(u32, prefix, 0);
    if (length > 0x100000) return error.InvalidBootData;
    h.* = try parseMultiboot2(try lowMemory(physical, length), physical);
}

/// Xen public arch-x86/hvm/start_info.h, version 1 memory map.
pub fn fillFromPvh(h: *BootHandoff, physical: u64) Error!void {
    const info = try lowMemory(physical, 56);
    if (try read(u32, info, 0) != 0x336ec578 or try read(u32, info, 4) < 1) return error.InvalidBootData;
    const count = try read(u32, info, 48);
    if (count == 0 or count > 4096) return error.InvalidBootData;
    const entries = try lowMemory(try read(u64, info, 40), @as(u64, count) * 24);
    var result = BootHandoff{ .flags = flag_pvh, .mb2_phys = physical };
    for (0..count) |i| {
        if (try read(u32, entries, i * 24 + 16) == 1) try append(&result, try read(u64, entries, i * 24), try read(u64, entries, i * 24 + 8));
    }
    const modules = try read(u32, info, 12);
    if (modules > 32) return error.InvalidBootData;
    try reserve(&result, physical, 56);
    try reserve(&result, try read(u64, info, 40), @as(u64, count) * 24);
    if (modules > 0) {
        const module = try lowMemory(try read(u64, info, 16), @as(u64, modules) * 32);
        result.ramdisk_address = try read(u64, module, 0);
        result.ramdisk_size = try read(u64, module, 8);
        try reserve(&result, try read(u64, info, 16), @as(u64, modules) * 32);
        for (0..modules) |i| try reserve(&result, try read(u64, module, i * 32), try read(u64, module, i * 32 + 8));
    }
    const rsdp = try read(u64, info, 32);
    if (rsdp != 0) {
        const rsdp_bytes = try lowMemory(rsdp, 36);
        @import("acpi.zig").discover(&result, rsdp_bytes.ptr) catch |err| {
            if (err != error.NoMadt) return error.InvalidBootData;
        };
    }
    if (result.region_count == 0) return error.NoUsableMemory;
    h.* = result;
}

test "Multiboot parser validates bounds and rejects RAM address overflow" {
    var bytes: [64]u8 = @splat(0);
    std.mem.writeInt(u32, bytes[0..4], 56, .little);
    std.mem.writeInt(u32, bytes[8..12], 6, .little);
    std.mem.writeInt(u32, bytes[12..16], 40, .little);
    std.mem.writeInt(u32, bytes[16..20], 24, .little);
    std.mem.writeInt(u64, bytes[24..32], 0x100000, .little);
    std.mem.writeInt(u64, bytes[32..40], 0x200000, .little);
    std.mem.writeInt(u32, bytes[40..44], 1, .little);
    std.mem.writeInt(u32, bytes[52..56], 8, .little);
    const h = try parseMultiboot2(&bytes, 0x1000);
    try std.testing.expectEqual(@as(u64, 0x300000), h.regions[0].end);
    try std.testing.expectError(error.InvalidBootData, parseMultiboot2(bytes[0..32], 0));
    std.mem.writeInt(u64, bytes[24..32], std.math.maxInt(u64), .little);
    try std.testing.expectError(error.InvalidBootData, parseMultiboot2(&bytes, 0));
}
