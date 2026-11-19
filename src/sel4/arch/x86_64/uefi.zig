//! Firmware image cache maintenance and architecture calling convention.
pub const elf_machine = @import("std").elf.EM.X86_64;
pub fn physical(address: u64) u64 {
    return address;
}
pub fn prepare(_: u64, _: usize) void {}
pub fn jump(entry: u64, handoff: u64) noreturn {
    asm volatile ("cli");
    const start: *const fn (u64) callconv(.{ .x86_64_sysv = .{} }) noreturn = @ptrFromInt(entry);
    start(handoff);
}
