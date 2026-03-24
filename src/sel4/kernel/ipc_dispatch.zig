//! 阶段三 优先级 4：IPC / 系统调用在上游对应 `api/syscall.c`（`handleSyscall`）与各 `object/*.c`。
//! 本文件为 Zig 侧调度骨架，与 `api/syscall.zig` 联通。
const syscall = @import("../api/syscall.zig");

pub const upstream_rel = "api/syscall.c";

pub fn handleFastSyscall(sys_word: i64, rdi: u64, rsi: u64, rdx: u64) void {
    syscall.dispatchFastCall(sys_word, rdi, rsi, rdx);
}

/// 对照 `fastpath.c` / `c_traps.c`：用户态 syscall 指令进入内核后的第一跳（当前转交 Zig 分发）。
pub fn handleTrapSyscallArgs(sys_word: i64, rdi: u64, rsi: u64, rdx: u64) void {
    handleFastSyscall(sys_word, rdi, rsi, rdx);
}
