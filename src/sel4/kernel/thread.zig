//! Shared priority queues with exclusive per-CPU ownership and affinity.
//! All operations require the kernel lock; architecture code performs the switch.
//! Reference: src/kernel/thread.c (non-MCS configuration).
const std = @import("std");
const s = @import("../model/structures.zig");
pub const upstream_rel = "kernel/thread.c";
pub const upstream_arch_rel = "arch/x86/kernel/thread.c";
pub const upstream_arch_64_rel = "arch/x86/64/kernel/thread.c";
pub const Thread = s.Thread;

pub const Scheduler = struct {
    const Queue = struct { head: ?*Thread = null, tail: ?*Thread = null };
    ready: [256]Queue = @splat(.{}),
    bitmap: [4]u64 = @splat(0),
    /// Alias for currents[cpu_index], selected only while holding the kernel lock.
    current: ?*Thread = null,
    idle: *Thread,
    cpu_index: u6 = 0,
    currents: [64]?*Thread = @splat(null),
    online_mask: u64 = 1,
    slice_ticks: u32 = 5,
    wake_mask: u64 = 0,

    pub fn init(idle: *Thread) Scheduler {
        idle.state = .idle;
        return .{ .idle = idle };
    }

    /// Save the caller's current selection before entering another CPU's state.
    pub fn selectCpu(self: *Scheduler, index: u6) void {
        std.debug.assert(self.online_mask & (@as(u64, 1) << index) != 0);
        self.currents[self.cpu_index] = self.current;
        self.cpu_index = index;
        self.current = self.currents[index];
    }

    pub fn setAffinity(self: *Scheduler, thread: *Thread, affinity: u64) error{RangeError}!void {
        if (affinity & self.online_mask == 0) return error.RangeError;
        thread.affinity = affinity & self.online_mask;
        self.wake_mask |= thread.affinity;
        if (thread.owner_cpu) |cpu| self.wake_mask |= @as(u64, 1) << cpu;
    }

    pub fn enqueue(self: *Scheduler, thread: *Thread) void {
        // A wakeup can race with a remote thread's pending trap. Its owner must
        // save that context and relinquish it before any CPU can dequeue it.
        if (thread.queued or thread == self.idle or thread.owner_cpu != null) return;
        std.debug.assert(thread.isRunnable());
        const q = &self.ready[thread.priority];
        thread.ready_prev = q.tail;
        thread.ready_next = null;
        if (q.tail) |tail| {
            tail.ready_next = thread;
        } else {
            q.head = thread;
        }
        q.tail = thread;
        thread.queued = true;
        self.wake_mask |= thread.affinity & self.online_mask;
        self.bitmap[thread.priority / 64] |= @as(u64, 1) << @as(u6, @truncate(thread.priority));
    }

    pub fn dequeue(self: *Scheduler, thread: *Thread) void {
        if (!thread.queued) return;
        const q = &self.ready[thread.priority];
        if (thread.ready_prev) |prev| {
            prev.ready_next = thread.ready_next;
        } else {
            q.head = thread.ready_next;
        }
        if (thread.ready_next) |next| {
            next.ready_prev = thread.ready_prev;
        } else {
            q.tail = thread.ready_prev;
        }
        thread.ready_prev = null;
        thread.ready_next = null;
        thread.queued = false;
        if (q.head == null) self.bitmap[thread.priority / 64] &= ~(@as(u64, 1) << @as(u6, @truncate(thread.priority)));
    }

    pub fn makeRunnable(self: *Scheduler, thread: *Thread) void {
        thread.state = .running;
        if (self.current != thread) self.enqueue(thread);
    }

    pub fn block(self: *Scheduler, thread: *Thread, state: s.ThreadState) void {
        self.dequeue(thread);
        thread.state = state;
        if (thread.owner_cpu) |cpu| self.wake_mask |= @as(u64, 1) << cpu;
    }

    fn highest(self: *const Scheduler) ?*Thread {
        var priority: usize = 256;
        while (priority > 0) {
            priority -= 1;
            if (self.bitmap[priority / 64] & (@as(u64, 1) << @as(u6, @truncate(priority))) == 0) continue;
            var candidate = self.ready[priority].head;
            while (candidate) |thread| : (candidate = thread.ready_next) {
                if (thread.affinity & (@as(u64, 1) << self.cpu_index) != 0) return thread;
            }
        }
        return null;
    }

    pub fn schedule(self: *Scheduler) *Thread {
        if (self.current) |current| {
            if (current.isRunnable() and current.affinity & (@as(u64, 1) << self.cpu_index) != 0) {
                const candidate = self.highest();
                if (candidate == null or current.priority >= candidate.?.priority) return current;
            }
            if (current != self.idle) {
                // The architecture trap has already saved the outgoing frame.
                // Only now may another CPU acquire this runnable thread.
                current.owner_cpu = null;
                if (current.isRunnable()) self.enqueue(current);
            }
        }
        const next = self.highest() orelse self.idle;
        self.dequeue(next);
        self.current = next;
        if (next != self.idle) {
            std.debug.assert(next.owner_cpu == null);
            next.owner_cpu = self.cpu_index;
        }
        if (next.state == .restart) next.state = .running;
        return next;
    }

    pub fn yield(self: *Scheduler) void {
        if (self.current) |current| {
            if (current.isRunnable()) {
                current.owner_cpu = null;
                current.time_slice = self.slice_ticks;
                self.enqueue(current);
            }
        }
        self.current = null;
        _ = self.schedule();
    }

    pub fn timerTick(self: *Scheduler) void {
        const current = self.current orelse return;
        if (!current.isRunnable()) return;
        if (current.time_slice > 1) {
            current.time_slice -= 1;
        } else {
            self.yield();
        }
    }

    pub fn setPriority(self: *Scheduler, thread: *Thread, priority: u8) void {
        const queued = thread.queued;
        self.dequeue(thread);
        thread.priority = priority;
        if (queued) self.enqueue(thread);
        // A remote owner may need to yield immediately after losing priority.
        if (thread.owner_cpu) |cpu| self.wake_mask |= @as(u64, 1) << cpu;
    }
};
