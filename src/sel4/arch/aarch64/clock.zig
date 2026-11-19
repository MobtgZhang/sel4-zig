//! The architected counter runs independently of timer interrupts and CPU loops.
pub fn initialize() !void {
    if (frequency() == 0) return error.InvalidCounterFrequency;
}
pub fn ticks() u64 {
    return asm volatile ("isb; mrs %[value], cntpct_el0"
        : [value] "=r" (-> u64),
        :
        : .{ .memory = true });
}
pub fn frequency() u64 {
    return asm volatile ("mrs %[value], cntfrq_el0"
        : [value] "=r" (-> u64),
    );
}
