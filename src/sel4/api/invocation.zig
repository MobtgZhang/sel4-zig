//! Common object invocation decoding for the fixed non-MCS configuration.
//! Validate every argument before committing changes; errors use seL4 wire labels.
const s = @import("../model/structures.zig");
const Kernel = @import("../kernel/runtime.zig").Kernel;
const cspace = @import("../kernel/cspace.zig");
const labels = @import("invocation_labels.zig");
const cnode = @import("../object/cnode.zig");
const untyped = @import("../object/untyped.zig");
const objecttype = @import("../object/objecttype.zig");

pub const Error = error{
    InvalidArgument,
    InvalidCapability,
    IllegalOperation,
    RangeError,
    AlignmentError,
    FailedLookup,
    TruncatedMessage,
    DeleteFirst,
    RevokeFirst,
    NotEnoughMemory,
    InvalidSize,
    InvalidDeviceObject,
};

pub const Request = struct {
    thread: *s.Thread,
    error_words: [6]u64 = @splat(0),
    error_length: u7 = 0,

    pub fn require(self: *Request, length: usize, extra_count: usize) Error!void {
        const available = if (self.thread.has_ipc_buffer) self.thread.message_info.length() else @min(self.thread.message_info.length(), 4);
        if (available < length or self.thread.message_info.extraCaps() < extra_count) return error.TruncatedMessage;
        for (0..extra_count) |i| {
            if (self.thread.extra_caps[i] == null) return error.TruncatedMessage;
        }
    }
    pub fn arg(self: *const Request, index: usize) u64 {
        return self.thread.message[index];
    }
    pub fn extra(self: *const Request, index: usize) s.Capability {
        return self.thread.extra_caps[index].?.cap;
    }
    pub fn range(self: *Request, minimum: u64, maximum: u64) Error {
        self.error_words[0..2].* = .{ minimum, maximum };
        self.error_length = 2;
        return error.RangeError;
    }
    pub fn invalidCap(self: *Request, index: u64) Error {
        self.error_words[0] = index;
        self.error_length = 1;
        return error.InvalidCapability;
    }
    pub fn invalidArgument(self: *Request, index: u64) Error {
        self.error_words[0] = index;
        self.error_length = 1;
        return error.InvalidArgument;
    }
    pub fn missingCap(self: *Request, source: bool, depth: u64) Error {
        self.error_words[0..3].* = .{ @intFromBool(source), 2, depth };
        self.error_length = 3;
        return error.FailedLookup;
    }
    pub fn slot(self: *Request, root: s.Capability, index: u64, depth: u64, source: bool) Error!*s.Slot {
        // Upstream diagnoses an invalid root before checking the requested depth.
        if (root != .cnode) {
            self.error_words[0..2].* = .{ @intFromBool(source), 1 };
            self.error_length = 2;
            return error.FailedLookup;
        }
        if (depth == 0 or depth > 64) return self.range(1, 64);
        const resolution = cspace.resolveAddressBits(root, index, @intCast(depth));
        self.error_words[0] = @intFromBool(source);
        switch (resolution) {
            .found => |found| {
                if (found.bits_remaining == 0) return found.slot;
                self.error_words[1..4].* = .{ 3, found.bits_remaining, 0 };
                self.error_length = 4;
            },
            .fault => |fault| switch (fault) {
                .invalid_root, .invalid_depth => {
                    self.error_words[1] = 1;
                    self.error_length = 2;
                },
                .depth_mismatch => |mismatch| {
                    self.error_words[1..4].* = .{ 3, mismatch.bits_left, mismatch.bits_found };
                    self.error_length = 4;
                },
                .guard_mismatch => |mismatch| {
                    self.error_words[1..5].* = .{ 4, mismatch.bits_left, mismatch.expected, mismatch.guard_size };
                    self.error_length = 5;
                },
            },
        }
        return error.FailedLookup;
    }
};

pub fn rights(word: u64) s.Rights {
    // CapRights has write/read/grant/grantReply in bits 0/1/2/3 respectively.
    return .{ .write = word & 1 != 0, .read = word & 2 != 0, .grant = word & 4 != 0, .grant_reply = word & 8 != 0 };
}

fn decodeUntyped(request: *Request, source: *s.Slot, label: u52) Error!void {
    if (label != labels.UntypedRetype) return error.IllegalOperation;
    try request.require(6, 1);
    const kind: objecttype.ObjectType = switch (request.arg(0)) {
        0 => .untyped,
        1 => .tcb,
        2 => .endpoint,
        3 => .notification,
        4 => .cnode,
        // Architecture frame/table types require architecture-specific decoders.
        else => return request.invalidArgument(0),
    };
    if (request.arg(1) > 47) return request.range(0, 47);
    const user_bits: u8 = @intCast(request.arg(1));
    _ = objecttype.storageBits(kind, user_bits) catch return request.invalidArgument(1);
    var node = request.extra(0);
    if (request.arg(3) != 0) {
        node = (try request.slot(node, request.arg(2), request.arg(3), false)).cap;
    }
    if (node != .cnode) return request.missingCap(false, request.arg(3));
    const offset = request.arg(4);
    const count = request.arg(5);
    if (offset >= node.cnode.slots.len) return request.range(0, node.cnode.slots.len - 1);
    if (count == 0 or count > untyped.max_fan_out) return request.range(1, untyped.max_fan_out);
    if (count > node.cnode.slots.len - offset) return request.range(1, node.cnode.slots.len - offset);
    untyped.retype(source, kind, user_bits, node.cnode.slots[@intCast(offset)..@intCast(offset + count)]) catch |err| {
        if (err == error.NotEnoughMemory) {
            const cap = source.cap.untyped;
            const used = if (cnode.hasChildren(source)) @min(cap.free_offset, cap.memory.len) else 0;
            request.error_words[0] = cap.memory.len - used;
            request.error_length = 1;
        }
        if (err == error.InvalidDeviceObject) return request.invalidArgument(1);
        return err;
    };
}

fn decodeIrq(kernel: *Kernel, request: *Request, source: *s.Slot, label: u52) Error!void {
    if (source.cap == .irq_control) {
        if (label != labels.IRQIssueIRQHandler) return error.IllegalOperation;
        try request.require(3, 1);
        const irq = request.arg(0);
        if (irq >= kernel.irqs.entries.len) return request.range(0, kernel.irqs.entries.len - 1);
        if (kernel.irqs.controller) |controller| {
            if (controller.valid) |valid| if (!valid(@intCast(irq))) return error.InvalidArgument;
        }
        const dest = try request.slot(request.extra(0), request.arg(1), request.arg(2), false);
        if (!dest.isEmpty()) return error.DeleteFirst;
        try kernel.irqs.issue(@intCast(irq));
        // The IRQ-control parent owns revocation of every issued handler.
        try cnode.insert(source, dest, .{ .irq_handler = @intCast(irq) });
        return;
    }
    const irq = source.cap.irq_handler;
    if (irq >= kernel.irqs.entries.len or !kernel.irqs.entries[irq].issued) return request.invalidCap(0);
    switch (label) {
        labels.IRQAckIRQ => try kernel.irqs.ack(irq),
        labels.IRQSetIRQHandler => {
            try request.require(0, 1);
            const cap = request.extra(0);
            if (cap != .notification or !cap.notification.rights.write) return request.invalidCap(1);
            try kernel.irqs.setNotification(irq, cap.notification);
        },
        labels.IRQClearIRQHandler => kernel.irqs.entries[irq].signal = null,
        else => return error.IllegalOperation,
    }
}

fn decode(kernel: *Kernel, request: *Request, source: *s.Slot, label: u52) Error!void {
    switch (source.cap) {
        .cnode => try @import("cnode_invocation.zig").decode(kernel, request, source.cap, label),
        .tcb => |target| try @import("tcb_invocation.zig").decode(kernel, request, target, label),
        .untyped => try decodeUntyped(request, source, label),
        .irq_control, .irq_handler => try decodeIrq(kernel, request, source, label),
        else => return error.IllegalOperation,
    }
}

fn errorLabel(err: Error) u52 {
    return switch (err) {
        error.InvalidArgument, error.InvalidSize, error.InvalidDeviceObject => 1,
        error.InvalidCapability => 2,
        error.IllegalOperation => 3,
        error.RangeError => 4,
        error.AlignmentError => 5,
        error.FailedLookup => 6,
        error.TruncatedMessage => 7,
        error.DeleteFirst => 8,
        error.RevokeFirst => 9,
        error.NotEnoughMemory => 10,
    };
}

/// Object errors are Call replies, never capability faults in the invocation path.
pub fn invoke(kernel: *Kernel, thread: *s.Thread, source: *s.Slot, call: bool) void {
    var request: Request = .{ .thread = thread };
    decode(kernel, &request, source, thread.message_info.label()) catch |err| {
        if (call) {
            var length = request.error_length;
            if (length == 0) length = switch (err) {
                error.InvalidArgument, error.InvalidCapability, error.InvalidSize, error.InvalidDeviceObject, error.NotEnoughMemory => 1,
                else => 0,
            };
            @memcpy(thread.message[0..length], request.error_words[0..length]);
            thread.message_info = s.MessageInfo.init(errorLabel(err), 0, 0, length);
            thread.badge = 0;
        }
        return;
    };
    if (call) {
        thread.message_info = .{};
        thread.badge = 0;
    }
}
