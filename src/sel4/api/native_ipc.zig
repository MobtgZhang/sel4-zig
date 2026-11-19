//! Marshal a mapped per-thread IPC buffer without dereferencing user pointers.
const s = @import("../model/structures.zig");
const cspace = @import("../kernel/cspace.zig");

/// Load from the kernel alias of this thread's mapped IPC buffer. Hardware MRs
/// take precedence over the first four buffer words, as in upstream libsel4.
pub fn load(thread: *s.Thread, buffer: *const s.IPCBuffer, tag: u64, words: [4]u64) void {
    thread.message_info = .{ .words = .{tag} };
    thread.has_ipc_buffer = true;
    @memcpy(&thread.message, &buffer.msg);
    @memcpy(thread.message[0..4], &words);
    loadExtraCaps(thread, buffer);
    loadReceiveSlot(thread, buffer);
}

fn loadExtraCaps(thread: *s.Thread, buffer: *const s.IPCBuffer) void {
    thread.extra_caps = @splat(null);
    thread.extra_cap_fault = null;
    for (0..thread.message_info.extraCaps()) |i| {
        thread.extra_caps[i] = cspace.lookupSlot(thread.cspace, buffer.caps_or_badges[i]) catch {
            // Do not raise a fault here: Send/Call must validate the invoked
            // CPtr first, and nonblocking sends must silently discard failure.
            thread.extra_cap_fault = buffer.caps_or_badges[i];
            break;
        };
    }
}

fn loadReceiveSlot(thread: *s.Thread, buffer: *const s.IPCBuffer) void {
    thread.receive_slot = null;
    // An invalid receive path drops capability transfer, not the IPC message.
    if (buffer.receiveDepth == 0 or buffer.receiveDepth > 64) return;
    const root = cspace.lookupSlot(thread.cspace, buffer.receiveCNode) catch return;
    thread.receive_slot = cspace.lookupSlotForCNodeOp(root.cap, buffer.receiveIndex, @intCast(buffer.receiveDepth)) catch null;
}

pub fn store(thread: *const s.Thread, buffer: *s.IPCBuffer) void {
    buffer.tag = thread.message_info;
    const count = thread.message_info.length();
    @memcpy(buffer.msg[0..count], thread.message[0..count]);
    @memcpy(&buffer.caps_or_badges, &thread.caps_or_badges);
}
