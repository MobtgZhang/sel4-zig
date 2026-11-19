//! Guarded capability lookup, following src/kernel/cspace.c:resolveAddressBits.
const s = @import("../model/structures.zig");
pub const upstream_rel = "kernel/cspace.c";
pub const LookupFault = union(enum) {
    invalid_root: void,
    guard_mismatch: struct { expected: u64, bits_left: u7, guard_size: u7 },
    depth_mismatch: struct { bits_found: u8, bits_left: u7 },
    invalid_depth: void,
};
pub const Resolution = union(enum) {
    found: struct { slot: *s.Slot, bits_remaining: u7 },
    fault: LookupFault,
};

pub fn resolveAddressBits(root: s.Capability, cptr: u64, depth: u7) Resolution {
    if (depth == 0 or depth > 64) return .{ .fault = .{ .invalid_depth = {} } };
    var node = switch (root) {
        .cnode => |cap| cap,
        else => return .{ .fault = .{ .invalid_root = {} } },
    };
    var remaining = depth;
    while (true) {
        const level: u8 = @as(u8, node.radix) + node.guard_size;
        if (node.guard_size > remaining) return .{ .fault = .{ .guard_mismatch = .{ .expected = node.guard, .bits_left = remaining, .guard_size = node.guard_size } } };
        const guard = if (node.guard_size == 0) 0 else (cptr >> @as(u6, @intCast(remaining - node.guard_size))) & s.mask(node.guard_size);
        if (guard != node.guard) return .{ .fault = .{ .guard_mismatch = .{ .expected = node.guard, .bits_left = remaining, .guard_size = node.guard_size } } };
        if (level == 0 or level > remaining) return .{ .fault = .{ .depth_mismatch = .{ .bits_found = level, .bits_left = remaining } } };
        const offset = (cptr >> @as(u6, @intCast(remaining - level))) & s.mask(node.radix);
        if (offset >= node.slots.len) return .{ .fault = .{ .depth_mismatch = .{ .bits_found = level, .bits_left = remaining } } };
        const slot = &node.slots[@intCast(offset)];
        remaining -= @intCast(level);
        if (remaining == 0 or slot.cap != .cnode) return .{ .found = .{ .slot = slot, .bits_remaining = remaining } };
        node = slot.cap.cnode;
    }
}

/// Thread lookup accepts early termination at a leaf, as upstream lookupSlot does.
pub fn lookupSlot(root: s.Capability, cptr: u64) error{FailedLookup}!*s.Slot {
    return switch (resolveAddressBits(root, cptr, 64)) {
        .found => |r| r.slot,
        .fault => error.FailedLookup,
    };
}

/// CNode operations require the requested depth to be consumed in full.
pub fn lookupSlotForCNodeOp(root: s.Capability, cptr: u64, depth: u7) error{FailedLookup}!*s.Slot {
    return switch (resolveAddressBits(root, cptr, depth)) {
        .found => |r| if (r.bits_remaining == 0) r.slot else error.FailedLookup,
        .fault => error.FailedLookup,
    };
}
