//! PSCI CPU_ON through the QEMU virt HVC conduit.
extern fn secondary_entry() void;
pub fn ticks() u64 {
    return asm volatile ("mrs %[value], cntpct_el0"
        : [value] "=r" (-> u64),
    );
}
pub var timeout_ticks: u64 = 0;
pub fn start(mpidr: u64, index: usize) !void {
    timeout_ticks = 2 * asm volatile ("mrs %[value], cntfrq_el0"
        : [value] "=r" (-> u64),
    );
    const status = asm volatile ("hvc #0"
        : [status] "={x0}" (-> i64),
        : [function] "{x0}" (@as(u64, 0xc4000003)),
          [target] "{x1}" (mpidr),
          [entry] "{x2}" (@intFromPtr(&secondary_entry)),
          [context] "{x3}" (index),
        : .{ .x1 = true, .x2 = true, .x3 = true, .memory = true });
    if (status != 0) return error.PsciCpuOnFailed;
}
