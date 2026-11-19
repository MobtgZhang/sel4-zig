//! Non-MCS syscall numbers with printing enabled, following syscall_header_gen.py.
//! Regenerate and compare the upstream headers before changing kernel configuration.
pub const seL4_SysCall: i64 = -1;
pub const seL4_SysReplyRecv: i64 = -2;
pub const seL4_SysSend: i64 = -3;
pub const seL4_SysNBSend: i64 = -4;
pub const seL4_SysRecv: i64 = -5;
pub const seL4_SysReply: i64 = -6;
pub const seL4_SysYield: i64 = -7;
pub const seL4_SysNBRecv: i64 = -8;
pub const seL4_SysDebugPutChar: i64 = -9;
