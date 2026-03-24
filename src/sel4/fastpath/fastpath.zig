//! 镜像：`seL4/src/fastpath/fastpath.c`（含快路径；汇编见同目录上游）
pub const upstream_rel = "fastpath/fastpath.c";

/// 快路径最终应与 `handleSyscall` 合流；迁移期直接走 `ipc_dispatch`。
pub fn enterFromFastpathStub(sys_word: i64, rdi: u64, rsi: u64, rdx: u64) void {
    @import("../kernel/ipc_dispatch.zig").handleTrapSyscallArgs(sys_word, rdi, rsi, rdx);
}

