//! Stable counter frequency comes from CPUCFG, not the instruction throughput.
fn config(index: u64) u64 {
    return asm volatile ("cpucfg %[value], %[index]"
        : [value] "=r" (-> u64),
        : [index] "r" (index),
    );
}
pub fn initialize() !void {
    const ratio = config(5);
    if (ratio >> 16 == 0 or ratio & 0xffff == 0 or config(4) == 0) return error.InvalidCounterFrequency;
}
pub fn ticks() u64 {
    return asm volatile ("rdtime.d %[value], $zero"
        : [value] "=r" (-> u64),
        :
        : .{ .memory = true });
}
pub fn frequency() u64 {
    const ratio = config(5);
    return config(4) * (ratio & 0xffff) / (ratio >> 16);
}
