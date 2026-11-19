//! Asynchronous badge accumulation and bound notifications.
//! Reference: src/object/notification.c, non-MCS configuration.
const s = @import("../model/structures.zig");
const Scheduler = @import("../kernel/thread.zig").Scheduler;
const endpoint = @import("endpoint.zig");
pub const upstream_rel = "object/notification.c";
pub const Notification = s.Notification;

pub fn bind(notification: *Notification, thread: *s.Thread) error{IllegalOperation}!void {
    if (notification.bound != null or thread.bound_notification != null or notification.state == .waiting) return error.IllegalOperation;
    notification.bound = thread;
    thread.bound_notification = notification;
}
pub fn unbind(notification: *Notification) void {
    if (notification.bound) |thread| thread.bound_notification = null;
    notification.bound = null;
}
pub fn signal(scheduler: *Scheduler, notification: *Notification, badge: u64) void {
    switch (notification.state) {
        .active => notification.badge |= badge,
        .waiting => {
            const receiver = notification.queue.pop().?;
            if (notification.queue.head == null) notification.state = .idle;
            receiver.notification = null;
            receiver.badge = badge;
            scheduler.makeRunnable(receiver);
        },
        .idle => {
            if (notification.bound) |thread| {
                if (thread.state == .blocked_receive) {
                    endpoint.cancel(scheduler, thread);
                    thread.badge = badge;
                    scheduler.makeRunnable(thread);
                    return;
                }
            }
            notification.badge = badge;
            notification.state = .active;
        },
    }
}
pub fn receive(scheduler: *Scheduler, thread: *s.Thread, notification: *Notification, blocking: bool) error{IllegalOperation}!void {
    if (notification.bound != null and notification.bound != thread) return error.IllegalOperation;
    if (notification.state == .active) {
        thread.badge = notification.badge;
        notification.badge = 0;
        notification.state = .idle;
    } else if (blocking) {
        thread.notification = notification;
        scheduler.block(thread, .blocked_notification);
        notification.queue.append(thread);
        notification.state = .waiting;
    } else thread.badge = 0;
}
pub fn cancel(scheduler: *Scheduler, thread: *s.Thread) void {
    const notification = thread.notification orelse return;
    notification.queue.remove(thread);
    if (notification.queue.head == null) notification.state = .idle;
    thread.notification = null;
    scheduler.block(thread, .inactive);
}
pub fn cancelAll(scheduler: *Scheduler, notification: *Notification) void {
    while (notification.queue.pop()) |thread| {
        thread.notification = null;
        thread.state = .restart;
        scheduler.enqueue(thread);
    }
    notification.state = .idle;
    notification.badge = 0;
    unbind(notification);
}
