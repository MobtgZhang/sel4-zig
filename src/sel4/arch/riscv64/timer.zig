//! SBI TIME extension; QEMU virt supplies a 10 MHz timebase.
pub fn initialize() void {
    rearm();
    asm volatile ("csrs sie, %[mask]"
        :
        : [mask] "r" (@as(u64, 1 << 5)),
        : .{ .memory = true });
}
pub fn rearm() void {
    const deadline = @import("smp.zig").ticks() +% 100_000;
    const result = asm volatile ("ecall"
        : [err] "={a0}" (-> isize),
        : [time] "{a0}" (deadline),
          [fid] "{a6}" (@as(u64, 0)),
          [eid] "{a7}" (@as(u64, 0x54494d45)),
        : .{ .a1 = true, .memory = true });
    if (result != 0) @panic("SBI set_timer failed");
}

pub const initializeLocal = initialize;
