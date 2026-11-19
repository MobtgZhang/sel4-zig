//! Firmware image cache maintenance and architecture calling convention.
pub const elf_machine = @import("std").elf.EM.AARCH64;
pub fn physical(address: u64) u64 {
    return address;
}
pub fn prepare(address: u64, length: usize) void {
    // Publish loaded instructions and data before the identity MMU is disabled.
    const ctr = asm volatile ("mrs %[v], ctr_el0"
        : [v] "=r" (-> u64),
    );
    const stride: u64 = @as(u64, 4) << @as(u6, @intCast((ctr >> 16) & 15));
    var line = address & ~(stride - 1);
    while (line < address + length) : (line += stride) asm volatile ("dc civac, %[v]"
        :
        : [v] "r" (line),
        : .{ .memory = true });
    asm volatile ("dsb sy; ic iallu; dsb sy; isb" ::: .{ .memory = true });
}
pub fn jump(entry: u64, handoff: u64) noreturn {
    asm volatile ("msr daifset, #0xf" ::: .{ .memory = true });
    const start: *const fn (u64) callconv(.c) noreturn = @ptrFromInt(entry);
    start(handoff);
}
