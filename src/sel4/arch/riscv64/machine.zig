//! riscv64 CPU idle primitive; interrupt-controller setup is platform work.
pub inline fn idle() void {
    asm volatile ("wfi" ::: .{ .memory = true });
}
