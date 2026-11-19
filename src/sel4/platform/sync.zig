//! FIFO ticket lock for short, non-sleeping critical sections on coherent CPUs.
//! Use lockIrqSave when an interrupt handler can acquire the same lock.
const std = @import("std");
pub const SpinLock = struct {
    next: u32 = 0,
    serving: u32 = 0,
    pub fn lock(self: *SpinLock) void {
        const ticket = @atomicRmw(u32, &self.next, .Add, 1, .monotonic);
        while (@atomicLoad(u32, &self.serving, .acquire) != ticket) @import("../arch/mod.zig").relax();
    }
    pub fn tryLock(self: *SpinLock) bool {
        const ticket = @atomicLoad(u32, &self.serving, .acquire);
        return @cmpxchgStrong(u32, &self.next, ticket, ticket +% 1, .acquire, .monotonic) == null;
    }
    pub fn unlock(self: *SpinLock) void {
        _ = @atomicRmw(u32, &self.serving, .Add, 1, .release);
    }
    pub fn lockIrqSave(self: *SpinLock) u64 {
        const flags = @import("../arch/mod.zig").backend.interrupts.saveDisable();
        self.lock();
        return flags;
    }
    pub fn unlockIrqRestore(self: *SpinLock, flags: u64) void {
        self.unlock();
        @import("../arch/mod.zig").backend.interrupts.restore(flags);
    }
};

test "ticket lock serializes contending CPUs and wraps without losing ownership" {
    var lock: SpinLock = .{ .next = std.math.maxInt(u32), .serving = std.math.maxInt(u32) };
    try std.testing.expect(lock.tryLock());
    try std.testing.expect(!lock.tryLock());
    lock.unlock();
    var counter: usize = 0;
    const Worker = struct {
        fn run(mutex: *SpinLock, value: *usize) void {
            for (0..2000) |_| {
                mutex.lock();
                value.* += 1;
                mutex.unlock();
            }
        }
    };
    var threads: [4]std.Thread = undefined;
    for (&threads) |*thread| thread.* = try std.Thread.spawn(.{}, Worker.run, .{ &lock, &counter });
    for (threads) |thread| thread.join();
    try std.testing.expectEqual(@as(usize, 8000), counter);
    try std.testing.expectEqual(@as(u32, 8000), lock.serving);
}
