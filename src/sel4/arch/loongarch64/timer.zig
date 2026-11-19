//! Per-CPU stable timer; CPUCFG gives the reference clock ratio.
fn config(index: u64) u64 {
    return asm volatile ("cpucfg %[v], %[i]"
        : [v] "=r" (-> u64),
        : [i] "r" (index),
    );
}
pub fn initialize() void {
    const ratio = config(5);
    const divisor = ratio >> 16;
    if (divisor == 0) @panic("invalid stable timer frequency");
    const frequency = config(4) * (ratio & 0xffff) / divisor;
    const value = (@max(4, frequency / 100) & ~@as(u64, 3)) | 3;
    asm volatile ("csrwr %[v], 0x41; csrwr %[mask], 0x4"
        :
        : [v] "r" (value),
          [mask] "r" (@as(u64, (1 << 11) | (1 << 12) | (1 << 2))),
        : .{ .memory = true });
}
pub fn acknowledge() void {
    asm volatile ("csrwr %[v], 0x44"
        :
        : [v] "r" (@as(u64, 1)),
        : .{ .memory = true });
}

pub const initializeLocal = initialize;
