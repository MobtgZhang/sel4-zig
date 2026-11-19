//! Scheduler-aware FIFO mutex. Contention blocks a thread instead of spinning.
//! Callers serialize scheduler access and may not sleep while holding a spinlock.
//! This native internal API does not add a syscall to the seL4 wire ABI.
const std = @import("std");
const s = @import("../model/structures.zig");
const Scheduler = @import("thread.zig").Scheduler;
pub const Mutex = s.Mutex;

fn attach(mutex: *Mutex, owner: *s.Thread) void {
    mutex.owner = owner;
    mutex.owned_prev = null;
    mutex.owned_next = owner.owned_mutexes;
    if (owner.owned_mutexes) |head| head.owned_prev = mutex;
    owner.owned_mutexes = mutex;
}
fn detach(mutex: *Mutex, owner: *s.Thread) void {
    if (mutex.owned_prev) |previous| previous.owned_next = mutex.owned_next else owner.owned_mutexes = mutex.owned_next;
    if (mutex.owned_next) |next| next.owned_prev = mutex.owned_prev;
    mutex.owner = null;
    mutex.owned_prev = null;
    mutex.owned_next = null;
}
pub fn tryLock(mutex: *Mutex, thread: *s.Thread) !bool {
    if (!thread.isRunnable() or thread.wait_mutex != null) return error.InvalidThreadState;
    if (mutex.owner == thread) return error.RecursiveLock;
    if (mutex.owner != null) return false;
    attach(mutex, thread);
    return true;
}
/// False means the caller must reschedule; unlock transfers ownership before wakeup.
pub fn lock(mutex: *Mutex, scheduler: *Scheduler, thread: *s.Thread) !bool {
    if (try tryLock(mutex, thread)) return true;
    scheduler.block(thread, .blocked_mutex);
    thread.wait_mutex = mutex;
    mutex.waiters.append(thread);
    return false;
}
pub fn unlock(mutex: *Mutex, scheduler: *Scheduler, thread: *s.Thread) !void {
    if (mutex.owner != thread) return error.NotOwner;
    detach(mutex, thread);
    if (mutex.waiters.pop()) |next| {
        std.debug.assert(next.wait_mutex == mutex and next.state == .blocked_mutex);
        next.wait_mutex = null;
        attach(mutex, next);
        scheduler.makeRunnable(next);
    }
}
pub fn cancelWait(scheduler: *Scheduler, thread: *s.Thread) void {
    const mutex = thread.wait_mutex orelse return;
    mutex.waiters.remove(thread);
    thread.wait_mutex = null;
    scheduler.block(thread, .inactive);
}
/// Destroying a TCB must not leave its pointers in a mutex or waiter queue.
pub fn releaseAll(scheduler: *Scheduler, thread: *s.Thread) void {
    cancelWait(scheduler, thread);
    while (thread.owned_mutexes) |mutex| unlock(mutex, scheduler, thread) catch unreachable;
}

pub fn selfTest() !void {
    var idle: s.Thread = .{};
    var scheduler = Scheduler.init(&idle);
    var owner: s.Thread = .{ .state = .running, .priority = 10 };
    var first: s.Thread = .{ .state = .running, .priority = 20 };
    var second: s.Thread = .{ .state = .running, .priority = 30 };
    var mutex: Mutex = .{};
    if (!try lock(&mutex, &scheduler, &owner)) return error.MutexFailed;
    if (try lock(&mutex, &scheduler, &first)) return error.MutexFailed;
    if (try lock(&mutex, &scheduler, &second)) return error.MutexFailed;
    try unlock(&mutex, &scheduler, &owner);
    if (mutex.owner != &first or first.state != .running or second.state != .blocked_mutex) return error.MutexFailed;
    cancelWait(&scheduler, &second);
    releaseAll(&scheduler, &first);
    if (mutex.owner != null or mutex.waiters.head != null or second.wait_mutex != null) return error.MutexFailed;
}

test "mutex blocks, hands ownership to FIFO waiter, and cancels safely" {
    try selfTest();
}
test "mutex rejects recursion and non-owner unlock; TCB deletion releases ownership" {
    const Kernel = @import("runtime.zig").Kernel;
    var idle: s.Thread = .{};
    var kernel = Kernel.init(&idle);
    var owner: s.Thread = .{ .state = .running };
    var waiter: s.Thread = .{ .state = .running };
    var mutex: Mutex = .{};
    var another: Mutex = .{};
    try std.testing.expect(try lock(&mutex, &kernel.scheduler, &owner));
    try std.testing.expect(try lock(&another, &kernel.scheduler, &owner));
    try std.testing.expectError(error.RecursiveLock, lock(&mutex, &kernel.scheduler, &owner));
    try std.testing.expectError(error.NotOwner, unlock(&mutex, &kernel.scheduler, &waiter));
    try std.testing.expect(!try lock(&mutex, &kernel.scheduler, &waiter));
    var cap = s.Slot.initRoot(.{ .tcb = &owner });
    kernel.delete(&cap);
    try std.testing.expect(owner.owned_mutexes == null and owner.state == .inactive);
    try std.testing.expect(mutex.owner == &waiter and another.owner == null);
    releaseAll(&kernel.scheduler, &waiter);
    try std.testing.expect(mutex.owner == null);
}
