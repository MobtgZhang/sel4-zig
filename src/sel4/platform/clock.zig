//! Monotonic deadlines remain valid with interrupts masked and across counter wrap.
const hardware = @import("../arch/mod.zig").backend.clock;
pub const initialize = hardware.initialize;
pub const ticks = hardware.ticks;

pub const Deadline = struct {
    started: u64,
    duration: u64,

    pub fn afterMilliseconds(milliseconds: u32) Deadline {
        const duration = @as(u128, hardware.frequency()) * milliseconds / 1000;
        return .{ .started = ticks(), .duration = @intCast(@min(duration, 0x7fffffffffffffff)) };
    }
    pub fn expired(self: Deadline) bool {
        return self.expiredAt(ticks());
    }
    pub fn expiredAt(self: Deadline, now: u64) bool {
        return now -% self.started >= self.duration;
    }
};

test "deadline does not expire early when the hardware counter wraps" {
    const std = @import("std");
    const deadline: Deadline = .{ .started = 0xfffffffffffffff0, .duration = 32 };
    try std.testing.expect(!deadline.expiredAt(0xffffffffffffffff));
    try std.testing.expect(!deadline.expiredAt(15));
    try std.testing.expect(deadline.expiredAt(16));
    try std.testing.expect(deadline.expiredAt(17));
}
