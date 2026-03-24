//! 与上游 `gen_headers/arch/api/syscall.h`（`syscall_header_gen.py`）在非 MCS、含 CONFIG_PRINTING 时一致。
//! AArch64 / RISC-V 的 `seL4_Sys*` 数值与 x86_64 相同（libsel4 头文件跨架构一致）；若启用 MCS 或不同配置请用 `zig build sel4-codegen` 对照生成头。
pub const seL4_SysCall: i64 = -1;
pub const seL4_SysReplyRecv: i64 = -2;
pub const seL4_SysSend: i64 = -3;
pub const seL4_SysNBSend: i64 = -4;
pub const seL4_SysRecv: i64 = -5;
pub const seL4_SysReply: i64 = -6;
pub const seL4_SysYield: i64 = -7;
pub const seL4_SysNBRecv: i64 = -8;
pub const seL4_SysDebugPutChar: i64 = -9;
