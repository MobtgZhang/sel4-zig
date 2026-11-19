//! Build a usable physical-memory set from a validated boot handoff.
//! References: src/kernel/boot.c and src/arch/x86/kernel/boot.c.
const handoff = @import("../boot/handoff.zig");
const memory = @import("boot_mem.zig");
pub const upstream_rel = "kernel/boot.c";
pub const upstream_arch_boot_rel = "arch/x86/kernel/boot.c";
pub const upstream_boot_sys_rel = "arch/x86/kernel/boot_sys.c";

pub fn usableMemory(h: *const handoff.BootHandoff, reserved: []const memory.PRegion) !memory.RegionSet {
    if (h.magic != handoff.magic or h.version != 3 or h.region_count > h.regions.len or h.reserved_count > h.reserved.len or h.cpu_count > h.cpu_ids.len) return error.InvalidHandoff;
    var available: memory.RegionSet = .{};
    for (h.regions[0..h.region_count]) |region| {
        if (region.start >= region.end) return error.InvalidRegion;
        try available.add(.{ .start = region.start, .end = region.end });
    }
    for (reserved) |region| try available.subtract(region);
    for (h.reserved[0..h.reserved_count]) |region| {
        if (region.start >= region.end) return error.InvalidRegion;
        try available.subtract(.{ .start = region.start, .end = region.end });
    }
    return available;
}
