//! Validate a bounded user read before a supervisor-mode dereference.
const std = @import("std");
const vm = @import("vspace.zig");

pub fn readable(space: *vm.AddressSpace, minimum: u64, address: u64, length: u64) bool {
    if (length > 4096 or address < minimum or !vm.isCanonical(address) or address > std.math.maxInt(u64) - length) return false;
    if (length == 0) return true;
    var page = address & ~@as(u64, 4095);
    const last = (address + length - 1) & ~@as(u64, 4095);
    while (true) : (page += 4096) {
        const mapping = space.resolve(page) catch return false;
        if (!mapping.user_access) return false;
        if (page == last) return true;
    }
}

pub fn writable(space: *vm.AddressSpace, minimum: u64, address: u64, length: u64) bool {
    if (length > 4096 or address < minimum or !vm.isCanonical(address) or address > std.math.maxInt(u64) - length) return false;
    if (length == 0) return true;
    var page = address & ~@as(u64, 4095);
    const last = (address + length - 1) & ~@as(u64, 4095);
    while (true) : (page += 4096) {
        const mapping = space.resolve(page) catch return false;
        if (!mapping.user_access or !mapping.writable) return false;
        if (page == last) return true;
    }
}

test "user reads reject supervisor pages, gaps, overflow and excessive lengths" {
    var tables: [8]vm.Table = undefined;
    var space = try vm.AddressSpace.init(&tables, 0x100000);
    try space.map(0x4000, 0x2000, .small, false, true, true);
    try space.map(0x5000, 0x3000, .small, true, false, true);
    try space.map(0x6000, 0x4000, .small, true, false, false);
    try std.testing.expect(readable(&space, 0x4000, 0x4fff, 2));
    try std.testing.expect(!readable(&space, 0x4000, 0x5fff, 2));
    try std.testing.expect(!readable(&space, 0x4000, 0x6000, 1));
    try std.testing.expect(!readable(&space, 0x4000, 0x7000, 1));
    try std.testing.expect(!readable(&space, 0x4000, 0x3fff, 1));
    try std.testing.expect(!readable(&space, 0x4000, std.math.maxInt(u64), 2));
    try std.testing.expect(!readable(&space, 0x4000, 0x800000000000, 1));
    try std.testing.expect(!readable(&space, 0x4000, 0x4000, 4097));
    try std.testing.expect(readable(&space, 0x4000, 0x4000, 4096));
}
