//! loongarch64 CPU idle primitive; interrupt-controller setup is platform work.
pub inline fn idle() void {
    asm volatile ("idle 0" ::: .{ .memory = true });
}
