//! Single-use caller authority for non-MCS Call/Reply IPC.
pub const upstream_rel = "object/reply.c";
const s = @import("../model/structures.zig");
const Scheduler = @import("../kernel/thread.zig").Scheduler;
const message = @import("../api/message.zig");

pub fn setup(scheduler: *Scheduler, caller: *s.Thread, server: *s.Thread, can_grant: bool) void {
    // Receive consumes the server's previous caller slot before accepting a call.
    discard(server);
    caller.reply_owner = server;
    server.caller = caller;
    server.reply_can_grant = can_grant;
    scheduler.block(caller, .blocked_reply);
}
pub fn discard(server: *s.Thread) void {
    if (server.caller) |caller| caller.reply_owner = null;
    server.caller = null;
    server.reply_can_grant = false;
}
pub fn invoke(scheduler: *Scheduler, server: *s.Thread) bool {
    const caller = server.caller orelse return false;
    if (caller.state != .blocked_reply or caller.reply_owner != server) {
        discard(server);
        return false;
    }
    const restart = if (caller.fault == .none) blk: {
        message.transfer(server, caller, null, 0, server.reply_can_grant);
        break :blk true;
    } else @import("../api/fault_ipc.zig").reply(server, caller);
    discard(server);
    if (restart) scheduler.makeRunnable(caller) else scheduler.block(caller, .inactive);
    return true;
}

/// Move the current caller's single-use authority into an empty CSpace slot.
pub fn save(server: *s.Thread, dest: *s.Slot) error{DeleteFirst}!void {
    if (!dest.isEmpty()) return error.DeleteFirst;
    const caller = server.caller orelse return;
    if (caller.state != .blocked_reply or caller.reply_owner != server) {
        discard(server);
        return;
    }
    dest.* = s.Slot.initRoot(.{ .reply = .{ .thread = caller, .can_grant = server.reply_can_grant } });
    caller.saved_reply_slot = dest;
    discard(server);
}

pub fn invokeSaved(scheduler: *Scheduler, server: *s.Thread, slot: *s.Slot) bool {
    if (slot.cap != .reply) return false;
    const cap = slot.cap.reply;
    const caller = cap.thread;
    if (caller.state != .blocked_reply or caller.saved_reply_slot != slot) return false;
    // Consume authority before waking the caller; repeated Send cannot reply twice.
    caller.saved_reply_slot = null;
    @import("cnode.zig").unlink(slot);
    const restart = if (caller.fault == .none) blk: {
        message.transfer(server, caller, null, 0, cap.can_grant);
        break :blk true;
    } else @import("../api/fault_ipc.zig").reply(server, caller);
    if (restart) scheduler.makeRunnable(caller) else scheduler.block(caller, .inactive);
    return true;
}
