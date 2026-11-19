//! Firmware image cache maintenance and architecture calling convention.
pub const elf_machine = @import("std").elf.EM.LOONGARCH;
pub fn physical(address: u64) u64 {
    return address & 0x0000ffffffffffff;
}
pub fn prepare(_: u64, _: usize) void {
    asm volatile ("dbar 0; ibar 0" ::: .{ .memory = true });
}
pub fn jump(entry: u64, handoff: u64) noreturn {
    asm volatile ("csrwr $zero, 0x4" ::: .{ .memory = true });
    // Firmware runs in direct mode; install both kernel windows before the high jump.
    asm volatile ("csrwr %[v], 0x180"
        :
        : [v] "r" (@as(u64, 0x8000000000000001)),
        : .{ .memory = true });
    asm volatile ("csrwr %[v], 0x181"
        :
        : [v] "r" (@as(u64, 0x9000000000000011)),
        : .{ .memory = true });
    // Enter the low alias until the assembly trampoline enables paged mode.
    const start: *const fn (u64) callconv(.c) noreturn = @ptrFromInt(physical(entry));
    start(physical(handoff) | 0x9000000000000000);
}
