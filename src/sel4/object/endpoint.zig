//! Blocking and nonblocking FIFO endpoint IPC (src/object/endpoint.c).
const s = @import("../model/structures.zig");
const Scheduler = @import("../kernel/thread.zig").Scheduler;
const message = @import("../api/message.zig");
const reply = @import("reply.zig");
pub const upstream_rel = "object/endpoint.c";
pub const Endpoint = s.Endpoint;

fn updateState(endpoint: *Endpoint) void {
    if (endpoint.queue.head == null) endpoint.state = .idle;
}
fn finishSend(scheduler: *Scheduler, sender: *s.Thread, receiver: *s.Thread, call: bool, rights: s.Rights, receive_grant: bool) void {
    if (call) {
        if (rights.grant or rights.grant_reply) reply.setup(scheduler, sender, receiver, receive_grant) else scheduler.block(sender, .inactive);
    } else scheduler.makeRunnable(sender);
}

pub fn send(scheduler: *Scheduler, sender: *s.Thread, cap: s.EndpointCap, blocking: bool, call: bool) error{InvalidCapability}!void {
    if (!cap.rights.write) return error.InvalidCapability;
    const endpoint = cap.object;
    if (endpoint.state == .receive) {
        const receiver = endpoint.queue.pop().?;
        updateState(endpoint);
        receiver.endpoint = null;
        message.transfer(sender, receiver, endpoint, cap.badge, cap.rights.grant);
        const receive_grant = receiver.pending_rights.grant;
        finishSend(scheduler, sender, receiver, call, cap.rights, receive_grant);
        scheduler.makeRunnable(receiver);
    } else if (blocking) {
        sender.endpoint = endpoint;
        sender.pending_badge = cap.badge;
        sender.pending_rights = cap.rights;
        sender.pending_call = call;
        scheduler.block(sender, .blocked_send);
        endpoint.state = .send;
        endpoint.queue.append(sender);
    }
}

pub fn receive(scheduler: *Scheduler, receiver: *s.Thread, cap: s.EndpointCap, blocking: bool) error{InvalidCapability}!void {
    if (!cap.rights.read) return error.InvalidCapability;
    reply.discard(receiver);
    if (receiver.bound_notification) |notification| {
        if (notification.state == .active) {
            receiver.badge = notification.badge;
            notification.badge = 0;
            notification.state = .idle;
            return;
        }
    }
    const endpoint = cap.object;
    if (endpoint.state == .send) {
        const sender = endpoint.queue.pop().?;
        updateState(endpoint);
        sender.endpoint = null;
        message.transfer(sender, receiver, endpoint, sender.pending_badge, sender.pending_rights.grant);
        finishSend(scheduler, sender, receiver, sender.pending_call, sender.pending_rights, cap.rights.grant);
    } else if (blocking) {
        receiver.endpoint = endpoint;
        receiver.pending_rights = cap.rights;
        scheduler.block(receiver, .blocked_receive);
        endpoint.state = .receive;
        endpoint.queue.append(receiver);
    } else message.failedReceive(receiver);
}

pub fn cancel(scheduler: *Scheduler, thread: *s.Thread) void {
    const endpoint = thread.endpoint orelse return;
    endpoint.queue.remove(thread);
    updateState(endpoint);
    thread.endpoint = null;
    scheduler.block(thread, .inactive);
}
pub fn cancelAll(scheduler: *Scheduler, endpoint: *Endpoint) void {
    while (endpoint.queue.pop()) |thread| {
        thread.endpoint = null;
        thread.state = .restart;
        scheduler.enqueue(thread);
    }
    endpoint.state = .idle;
}
pub fn cancelBadgedSends(scheduler: *Scheduler, endpoint: *Endpoint, badge: u64) void {
    if (endpoint.state != .send) return;
    var next = endpoint.queue.head;
    while (next) |thread| {
        next = thread.wait_next;
        if (thread.pending_badge == badge) {
            endpoint.queue.remove(thread);
            thread.endpoint = null;
            thread.state = .restart;
            scheduler.enqueue(thread);
        }
    }
    updateState(endpoint);
}
