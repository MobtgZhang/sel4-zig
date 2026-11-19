//! Capability rights, badge derivation, and object identity.
//! Reference: src/object/objecttype.c and include/object/structures_64.bf.
const std = @import("std");
const s = @import("structures.zig");
pub const Capability = s.Capability;
pub const Rights = s.Rights;
pub const Slot = s.Slot;
pub const CNodeCap = s.CNodeCap;

pub fn maskRights(cap: Capability, rights: Rights) Capability {
    var result = cap;
    switch (result) {
        .endpoint => |*c| c.rights = c.rights.intersect(rights),
        .notification => |*c| c.rights = c.rights.intersect(rights),
        .frame => |*c| c.rights = c.rights.intersect(rights),
        else => {},
    }
    return result;
}

pub fn updateData(cap: Capability, preserve: bool, data: u64) error{IllegalOperation}!Capability {
    var result = cap;
    switch (result) {
        .endpoint => |*c| {
            if (preserve or c.badge != 0) return error.IllegalOperation;
            c.badge = data;
        },
        .notification => |*c| {
            if (preserve or c.badge != 0) return error.IllegalOperation;
            c.badge = data;
        },
        .cnode => |*c| {
            const size: u7 = @intCast(data & 63);
            if (@as(u8, size) + c.radix > 64) return error.IllegalOperation;
            c.guard_size = size;
            c.guard = (data >> 6) & s.mask(size);
        },
        else => {},
    }
    return result;
}

pub fn physicalRange(cap: Capability) ?struct { base: usize, size: usize } {
    return switch (cap) {
        .untyped => |c| .{ .base = @intFromPtr(c.memory.ptr), .size = c.memory.len },
        .frame => |c| .{ .base = @intFromPtr(c.memory.ptr), .size = c.memory.len },
        .endpoint => |c| .{ .base = @intFromPtr(c.object), .size = @sizeOf(s.Endpoint) },
        .notification => |c| .{ .base = @intFromPtr(c.object), .size = @sizeOf(s.Notification) },
        .tcb => |c| .{ .base = @intFromPtr(c), .size = @sizeOf(s.Thread) },
        .cnode => |c| .{ .base = @intFromPtr(c.slots.ptr), .size = c.slots.len * @sizeOf(Slot) },
        else => null,
    };
}

/// Region inclusion is directional for untyped and IRQ-control capabilities.
pub fn sameRegionAs(a: Capability, b: Capability) bool {
    if (a == .untyped) {
        const ar = physicalRange(a).?;
        const br = physicalRange(b) orelse return false;
        return br.base >= ar.base and br.size <= ar.size and br.base - ar.base <= ar.size - br.size;
    }
    if (a == .irq_control) return b == .irq_control or b == .irq_handler;
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .null_cap => false,
        .endpoint => |c| c.object == b.endpoint.object,
        .notification => |c| c.object == b.notification.object,
        .tcb => |c| c == b.tcb,
        .cnode => |c| c.slots.ptr == b.cnode.slots.ptr and c.radix == b.cnode.radix,
        .frame => |c| c.memory.ptr == b.frame.memory.ptr and c.memory.len == b.frame.memory.len,
        .reply => |c| c.thread == b.reply.thread,
        .irq_handler => |irq| irq == b.irq_handler,
        .domain => true,
        .untyped, .irq_control => unreachable,
    };
}

pub fn isRevocable(derived: Capability, source: Capability) bool {
    if (source == .untyped) return true;
    return switch (derived) {
        .endpoint => |c| source == .endpoint and c.badge != source.endpoint.badge,
        .notification => |c| source == .notification and c.badge != source.notification.badge,
        .irq_handler => source == .irq_control,
        else => source == .untyped,
    };
}

/// Untyped and IRQ-control caps describe authority, not a finalizable object.
pub fn sameObjectAs(a: Capability, b: Capability) bool {
    if (a == .untyped or a == .irq_control) return false;
    return sameRegionAs(a, b);
}
