//! QEMU virt exposes a 10 MHz architectural timebase through the TIME CSR.
//! Other platforms must provide their device-tree timebase before being enabled.
pub fn initialize() !void {}
pub fn frequency() u64 {
    return 10_000_000;
}
pub fn ticks() u64 {
    return asm volatile ("rdtime %[value]"
        : [value] "=r" (-> u64),
        :
        : .{ .memory = true });
}
