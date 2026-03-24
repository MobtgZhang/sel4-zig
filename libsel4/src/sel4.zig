//! 阶段五 5.2：用户态 syscall 接口（libsel4 的 Zig 等价物）。
//! idea1.md 5.2 中仅用 `rdi`/`rsi` 的草图**不是**真实 seL4 x86_64 约定；实现见 `syscall_x86_64.zig`（与上游 `x64_sys_send` 一致）。
const builtin = @import("builtin");

const impl = switch (builtin.cpu.arch) {
    .x86_64 => @import("syscall_x86_64.zig"),
    .aarch64 => @import("syscall_aarch64.zig"),
    .riscv64 => @import("syscall_riscv64.zig"),
    else => @import("syscall_stub.zig"),
};

pub const seL4_Word = impl.seL4_Word;
pub const seL4_CPtr = impl.seL4_CPtr;
pub const MessageInfo = impl.MessageInfo;
pub const seL4_SysSend = impl.seL4_SysSend;
pub const seL4_SysDebugPutChar = impl.seL4_SysDebugPutChar;
pub const seL4_Send = impl.seL4_Send;
pub const seL4_SendWithMRs = impl.seL4_SendWithMRs;
