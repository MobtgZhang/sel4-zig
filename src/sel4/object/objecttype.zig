//! Storage sizing and construction for native Zig objects.
//! Native object sizes intentionally differ from seL4's packed C ABI.
const std = @import("std");
const s = @import("../model/structures.zig");
pub const upstream_rel = "object/objecttype.c";
pub const upstream_arch_64_rel = "arch/x86/64/object/objecttype.c";
pub const ObjectType = enum { untyped, endpoint, notification, tcb, cnode, frame };
pub const Error = error{ InvalidSize, InvalidDeviceObject };

pub fn storageBits(kind: ObjectType, user_bits: u8) Error!u6 {
    const bytes: usize = switch (kind) {
        .untyped => {
            if (user_bits < 4 or user_bits > 47) return error.InvalidSize;
            return @intCast(user_bits);
        },
        .frame => {
            if (user_bits != 12 and user_bits != 21 and user_bits != 30) return error.InvalidSize;
            return @intCast(user_bits);
        },
        .endpoint => @sizeOf(s.Endpoint),
        .notification => @sizeOf(s.Notification),
        .tcb => @sizeOf(s.Thread),
        .cnode => {
            if (user_bits == 0 or user_bits > 20) return error.InvalidSize;
            const count = @as(usize, 1) << @as(u6, @intCast(user_bits));
            return @intCast(std.math.log2_int_ceil(usize, @sizeOf(s.Slot) * count));
        },
    };
    return @intCast(@max(4, std.math.log2_int_ceil(usize, bytes)));
}

/// All validation must finish before this infallible commit step.
pub fn create(kind: ObjectType, user_bits: u8, memory: []align(16) u8, device: bool) s.Capability {
    if (!device) @memset(memory, 0);
    return switch (kind) {
        .untyped => .{ .untyped = .{ .memory = memory, .device = device } },
        .frame => .{ .frame = .{ .memory = memory, .device = device } },
        .endpoint => blk: {
            const object: *s.Endpoint = @ptrCast(memory.ptr);
            object.* = .{};
            break :blk .{ .endpoint = .{ .object = object } };
        },
        .notification => blk: {
            const object: *s.Notification = @ptrCast(memory.ptr);
            object.* = .{};
            break :blk .{ .notification = .{ .object = object } };
        },
        .tcb => blk: {
            const object: *s.Thread = @ptrCast(memory.ptr);
            object.* = .{};
            break :blk .{ .tcb = object };
        },
        .cnode => blk: {
            const count = @as(usize, 1) << @as(u6, @intCast(user_bits));
            const slots = @as([*]s.Slot, @ptrCast(memory.ptr))[0..count];
            for (slots) |*slot| slot.* = .{};
            break :blk .{ .cnode = s.CNodeCap.init(slots, 0, 0) catch unreachable };
        },
    };
}
