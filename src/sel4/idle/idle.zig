//! Architecture idle loop; reference src/arch/x86/idle.c.
const builtin = @import("builtin");

pub const upstream_rel = "arch/x86/idle.c";
pub const upstream_asm_rel = "arch/x86/idle.S";

/// Execute privileged idle instructions only inside the kernel.
pub fn idleHaltOnce() void {
    if (builtin.cpu.arch == .x86_64) {
        asm volatile ("hlt" ::: .{ .memory = true });
    }
}
