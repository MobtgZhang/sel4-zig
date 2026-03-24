//! 上游：`seL4/src/arch/x86/idle.c`；汇编见 `upstream_asm_rel`。
const builtin = @import("builtin");

pub const upstream_rel = "arch/x86/idle.c";
pub const upstream_asm_rel = "arch/x86/idle.S";

/// 对照 `idle` 循环：仅在 x86_64 目标下使用 `hlt`（主机单测勿调用）。
pub fn idleHaltOnce() void {
    if (builtin.cpu.arch == .x86_64) {
        asm volatile ("hlt" ::: .{ .memory = true });
    }
}
