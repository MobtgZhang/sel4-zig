//! Capability derivation and intrusive MDB operations (src/object/cnode.c).
//! Final object teardown is supplied by the runtime before unlinking a slot.
const s = @import("../model/structures.zig");
const caps = @import("../model/capability.zig");
pub const upstream_rel = "object/cnode.c";
pub const upstream_arch_objecttype_rel = "arch/x86/64/object/objecttype.c";
pub const Error = error{ DeleteFirst, RevokeFirst, InvalidCapability, IllegalOperation };

pub fn isParentOf(parent: *const s.Slot, child: *const s.Slot) bool {
    if (!parent.revocable or !caps.sameRegionAs(parent.cap, child.cap)) return false;
    return switch (parent.cap) {
        .endpoint => |c| c.badge == 0 or (c.badge == child.cap.endpoint.badge and !child.first_badged),
        .notification => |c| c.badge == 0 or (c.badge == child.cap.notification.badge and !child.first_badged),
        else => true,
    };
}
pub fn hasChildren(slot: *const s.Slot) bool {
    return if (slot.next) |next| isParentOf(slot, next) else false;
}
pub fn derive(source: *s.Slot, cap: s.Capability) Error!s.Capability {
    switch (cap) {
        .null_cap, .reply, .irq_control => return error.InvalidCapability,
        .untyped => if (hasChildren(source)) return error.RevokeFirst,
        else => {},
    }
    return cap;
}
pub fn insert(source: *s.Slot, dest: *s.Slot, cap: s.Capability) Error!void {
    if (!dest.isEmpty()) return error.DeleteFirst;
    if (!source.cap.isValid() or !cap.isValid()) return error.InvalidCapability;
    const revocable = caps.isRevocable(cap, source.cap);
    dest.* = .{ .cap = cap, .prev = source, .next = source.next, .revocable = revocable, .first_badged = revocable };
    if (source.next) |next| next.prev = dest;
    source.next = dest;
    // Root authority imported by the native caller has no MDB predecessor.
    // Every untyped cap must remain a revocable parent of its allocations.
    if (source.cap == .untyped) source.revocable = true;
    // An untyped alias must never allocate overlapping objects through its parent.
    if (source.cap == .untyped and cap == .untyped and source.cap.untyped.memory.ptr == cap.untyped.memory.ptr and source.cap.untyped.memory.len == cap.untyped.memory.len) {
        source.cap.untyped.free_offset = source.cap.untyped.memory.len;
    }
}
pub fn copy(source: *s.Slot, dest: *s.Slot, rights: s.Rights) Error!void {
    const cap = try derive(source, caps.maskRights(source.cap, rights));
    try insert(source, dest, cap);
}
pub fn mint(source: *s.Slot, dest: *s.Slot, rights: s.Rights, data: u64) Error!void {
    const cap = try derive(source, try caps.updateData(caps.maskRights(source.cap, rights), false, data));
    try insert(source, dest, cap);
}
pub fn move(source: *s.Slot, dest: *s.Slot) Error!void {
    if (!dest.isEmpty()) return error.DeleteFirst;
    if (!source.cap.isValid()) return error.InvalidCapability;
    dest.* = source.*;
    if (dest.prev) |prev| prev.next = dest;
    if (dest.next) |next| next.prev = dest;
    source.* = .{};
    if (dest.cap == .reply and dest.cap.reply.thread.saved_reply_slot == source) {
        dest.cap.reply.thread.saved_reply_slot = dest;
    }
}

pub fn isFinal(slot: *const s.Slot) bool {
    if (slot.prev) |prev| if (caps.sameObjectAs(prev.cap, slot.cap)) return false;
    if (slot.next) |next| if (caps.sameObjectAs(slot.cap, next.cap)) return false;
    return true;
}

/// The caller must finalize the last capability to a live kernel object first.
pub fn unlink(slot: *s.Slot) void {
    if (slot.prev) |prev| prev.next = slot.next;
    if (slot.next) |next| {
        next.prev = slot.prev;
        next.first_badged = next.first_badged or slot.first_badged;
    }
    slot.* = .{};
}

/// Rotate two existing authorities, repairing MDB neighbours even for adjacent slots.
/// The temporary slot is local to this locked transaction and cannot escape.
pub fn rotate(source: *s.Slot, pivot: *s.Slot, dest: *s.Slot, source_cap: s.Capability, pivot_cap: s.Capability) Error!void {
    if (pivot == source or pivot == dest) return error.IllegalOperation;
    if (!source.cap.isValid() or !pivot.cap.isValid()) return error.InvalidCapability;
    if (source != dest and !dest.isEmpty()) return error.DeleteFirst;
    if (source == dest) {
        var temporary: s.Slot = .{};
        try move(source, &temporary);
        try move(pivot, dest);
        try move(&temporary, pivot);
    } else {
        try move(pivot, dest);
        try move(source, pivot);
    }
    dest.cap = pivot_cap;
    pivot.cap = source_cap;
}
