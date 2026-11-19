//! aarch64 CPU idle primitive; interrupt-controller setup is platform work.
pub inline fn idle() void {
    asm volatile ("wfe" ::: .{ .memory = true });
}
