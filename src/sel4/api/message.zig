//! Message metadata and normal IPC transfer (src/kernel/thread.c).
const s = @import("../model/structures.zig");
const cnode = @import("../object/cnode.zig");
pub const MessageInfo = s.MessageInfo;

pub fn transfer(sender: *s.Thread, receiver: *s.Thread, endpoint: ?*s.Endpoint, badge: u64, can_grant: bool) void {
    if (sender.fault != .none) {
        @import("fault_ipc.zig").transfer(sender, receiver, badge);
        return;
    }

    const available: usize = if (sender.has_ipc_buffer and receiver.has_ipc_buffer) s.max_message_words else 4;
    const length = @min(sender.message_info.length(), available);
    @memcpy(receiver.message[0..length], sender.message[0..length]);
    receiver.badge = badge;
    var transferred: u2 = 0;
    var unwrapped: u3 = 0;
    // Upstream allows many endpoint badges but only one inserted capability.
    var dest = if (receiver.has_ipc_buffer) receiver.receive_slot else null;
    if (can_grant and sender.has_ipc_buffer and receiver.has_ipc_buffer) {
        // Resolve all extra capabilities before transferring any authority.
        // This native interface receives slots already looked up by its caller.
        for (0..sender.message_info.extraCaps()) |i| {
            if (sender.extra_caps[i] == null or !sender.extra_caps[i].?.cap.isValid()) {
                receiver.message_info = MessageInfo.init(sender.message_info.label(), 0, 0, @intCast(length));
                return;
            }
        }
        for (0..sender.message_info.extraCaps()) |i| {
            const source = sender.extra_caps[i] orelse break;
            if (source.cap == .endpoint and endpoint != null and source.cap.endpoint.object == endpoint.?) {
                receiver.caps_or_badges[i] = source.cap.endpoint.badge;
                unwrapped |= @as(u3, 1) << @as(u2, @intCast(i));
            } else {
                const slot = dest orelse break;
                cnode.copy(source, slot, .{}) catch break;
                dest = null;
            }
            transferred += 1;
        }
    }
    receiver.message_info = MessageInfo.init(sender.message_info.label(), unwrapped, transferred, @intCast(length));
}

pub fn failedReceive(thread: *s.Thread) void {
    // seL4's nonblocking receive failure returns a zero badge.
    thread.badge = 0;
}
