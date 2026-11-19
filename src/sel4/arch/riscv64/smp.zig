//! Supervisor Binary Interface HSM startup on the QEMU virt platform.
extern fn secondary_entry() void;
pub fn ticks() u64 {
    return asm volatile ("rdtime %[value]"
        : [value] "=r" (-> u64),
    );
}
// QEMU virt's architectural timebase is 10 MHz.
pub const timeout_ticks: u64 = 20_000_000;
pub fn start(hart: u64, index: usize) !void {
    const result = asm volatile ("ecall"
        : [err] "={a0}" (-> isize),
        : [hart] "{a0}" (hart),
          [entry] "{a1}" (@intFromPtr(&secondary_entry)),
          [context] "{a2}" (index),
          [fid] "{a6}" (@as(usize, 0)),
          [eid] "{a7}" (@as(usize, 0x48534d)),
        : .{ .a1 = true, .memory = true });
    if (result != 0) return error.SbiHartStartFailed;
}
