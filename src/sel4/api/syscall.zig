//! 上游：`seL4/src/api/syscall.c`（`handleSyscall` / `handleUnknownSyscall`）；此处为可单测的分发骨架。
//! 阶段五用户态 `seL4_Send` 等见 `libsel4/src/sel4.zig`。
const nums = @import("syscall_nums");

pub const upstream_rel = "api/syscall.c";

pub const DispatchTag = enum {
    none,
    debug_putchar,
    ipc_unimplemented,
    unknown_syscall,
};

pub var last_dispatch_tag: DispatchTag = .none;

var debug_putchar_trace: [64]u8 = undefined;
var debug_putchar_len: usize = 0;

pub fn testTraceReset() void {
    debug_putchar_len = 0;
    last_dispatch_tag = .none;
}

pub fn testTraceSlice() []const u8 {
    return debug_putchar_trace[0..debug_putchar_len];
}

/// 对照 `handleSyscall` 主 `switch`：IPC 类 syscall 仅占位，便于接 `handleInvocation` / `handleRecv`。
pub fn dispatchKernelSyscall(sys_word: i64, rdi: u64, rsi: u64, rdx: u64) DispatchTag {
    _ = .{ rsi, rdx };
    switch (sys_word) {
        nums.seL4_SysDebugPutChar => {
            const c: u8 = @truncate(rdi);
            if (debug_putchar_len < debug_putchar_trace.len) {
                debug_putchar_trace[debug_putchar_len] = c;
                debug_putchar_len += 1;
            }
            return .debug_putchar;
        },
        nums.seL4_SysCall,
        nums.seL4_SysReplyRecv,
        nums.seL4_SysSend,
        nums.seL4_SysNBSend,
        nums.seL4_SysRecv,
        nums.seL4_SysReply,
        nums.seL4_SysYield,
        nums.seL4_SysNBRecv,
        => return .ipc_unimplemented,
        else => return .unknown_syscall,
    }
}

/// 供主机单测或未来陷阱入口调用。
pub fn dispatchFastCall(sys_word: i64, rdi: u64, rsi: u64, rdx: u64) void {
    last_dispatch_tag = dispatchKernelSyscall(sys_word, rdi, rsi, rdx);
}
