//! Non-MCS fault IPC wire format and single-use fault replies.
//! References: src/api/faults.c and src/kernel/faulthandler.c in upstream seL4.
const s = @import("../model/structures.zig");
const Scheduler = @import("../kernel/thread.zig").Scheduler;
const cspace = @import("../kernel/cspace.zig");
const endpoint = @import("../object/endpoint.zig");

pub fn deliver(scheduler: *Scheduler, thread: *s.Thread) error{NoFaultHandler}!void {
    const slot = cspace.lookupSlot(thread.cspace, thread.fault_handler) catch {
        scheduler.block(thread, .inactive);
        return error.NoFaultHandler;
    };
    if (slot.cap != .endpoint or !slot.cap.endpoint.rights.write or
        !(slot.cap.endpoint.rights.grant or slot.cap.endpoint.rights.grant_reply))
    {
        scheduler.block(thread, .inactive);
        return error.NoFaultHandler;
    }
    endpoint.send(scheduler, thread, slot.cap.endpoint, true, true) catch unreachable;
}

pub fn transfer(sender: *const s.Thread, receiver: *s.Thread, badge: u64) void {
    var words: [20]u64 = @splat(0);
    var label: u52 = 0;
    var length: usize = 0;
    switch (sender.fault) {
        .none => unreachable,
        .vm => |fault| {
            label = 5;
            words[0..4].* = .{ sender.fault_pc, fault.address, @intFromBool(fault.instruction), fault.status };
            length = 4;
        },
        .capability => |fault| {
            label = 1;
            words[0..7].* = .{ sender.fault_pc, fault.address, @intFromBool(fault.in_receive), fault.lookup_type, fault.bits_left, fault.guard_found, fault.bits_found };
            length = switch (fault.lookup_type) {
                1 => 4,
                2 => 5,
                3 => 6,
                else => 7,
            };
            if (fault.lookup_type == 3) words[5] = fault.bits_found;
        },
        .unknown_syscall => |number| {
            label = 2;
            length = @min(sender.fault_register_count, 18);
            @memcpy(words[0..length], sender.fault_registers[0..length]);
            words[length] = @bitCast(number);
            length += 1;
        },
        .user_exception => |fault| {
            label = 3;
            length = @min(sender.fault_register_count, 18);
            @memcpy(words[0..length], sender.fault_registers[0..length]);
            words[length] = fault.number;
            words[length + 1] = fault.code;
            length += 2;
        },
    }
    length = @min(length, if (receiver.has_ipc_buffer) @as(usize, s.max_message_words) else 4);
    @memcpy(receiver.message[0..length], words[0..length]);
    receiver.badge = badge;
    receiver.extra_caps = @splat(null);
    receiver.caps_or_badges = @splat(0);
    receiver.message_info = s.MessageInfo.init(label, 0, 0, @intCast(length));
}

/// VM/capability replies retry; exception/syscall replies accept label zero only.
pub fn reply(server: *const s.Thread, caller: *s.Thread) bool {
    const restart = switch (caller.fault) {
        .vm, .capability => true,
        .unknown_syscall, .user_exception => blk: {
            const available = if (server.has_ipc_buffer) @as(usize, s.max_message_words) else 4;
            const count = @min(@min(server.message_info.length(), available), caller.fault_register_count);
            @memcpy(caller.fault_registers[0..count], server.message[0..count]);
            caller.fault_reply_pending = true;
            break :blk server.message_info.label() == 0;
        },
        .none => unreachable,
    };
    caller.fault = .{ .none = {} };
    return restart;
}
