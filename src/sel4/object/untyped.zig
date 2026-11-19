//! Transactional untyped retyping into caller-owned native object storage.
//! Reference: src/object/untyped.c:decodeUntypedInvocation/invokeUntyped_Retype.
const std = @import("std");
const s = @import("../model/structures.zig");
const cnode = @import("cnode.zig");
const objecttype = @import("objecttype.zig");
pub const upstream_rel = "object/untyped.c";
pub const upstream_arch_objecttype_rel = "arch/x86/object/objecttype.c";
pub const word_bits = 64;
pub const max_fan_out = 256;
pub const Error = objecttype.Error || cnode.Error || error{ NotEnoughMemory, RangeError };

pub fn retype(source: *s.Slot, kind: objecttype.ObjectType, user_bits: u8, dest: []s.Slot) Error!void {
    if (source.cap != .untyped) return error.InvalidCapability;
    if (dest.len == 0 or dest.len > max_fan_out) return error.RangeError;
    for (dest) |*slot| if (!slot.isEmpty()) return error.DeleteFirst;
    const cap = source.cap.untyped;
    if (cap.device and kind != .untyped and kind != .frame) return error.InvalidDeviceObject;
    const bits = try objecttype.storageBits(kind, user_bits);
    const object_size = @as(usize, 1) << bits;
    const offset = if (cnode.hasChildren(source)) cap.free_offset else 0;
    if (offset > cap.memory.len) return error.NotEnoughMemory;
    const base = @intFromPtr(cap.memory.ptr);
    const free = std.math.add(usize, base, offset) catch return error.NotEnoughMemory;
    const aligned = std.math.add(usize, free, object_size - 1) catch return error.NotEnoughMemory;
    const start = (aligned & ~(object_size - 1)) - base;
    if (start > cap.memory.len or dest.len > (cap.memory.len - start) / object_size) return error.NotEnoughMemory;
    const end = start + dest.len * object_size;
    // A destination CNode must not reside in memory that this retype would clear.
    const dest_start = @intFromPtr(dest.ptr);
    const dest_end = dest_start + dest.len * @sizeOf(s.Slot);
    if (dest_start < base + end and dest_end > base + start) return error.IllegalOperation;
    for (dest, 0..) |*slot, i| {
        const pos = start + i * object_size;
        const memory: []align(16) u8 = @alignCast(cap.memory[pos .. pos + object_size]);
        const new_cap = objecttype.create(kind, user_bits, memory, cap.device);
        cnode.insert(source, slot, new_cap) catch unreachable;
    }
    source.cap.untyped.free_offset = end;
}
