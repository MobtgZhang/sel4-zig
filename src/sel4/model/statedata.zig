//! 镜像：`seL4/src/model/statedata.c`；x86：`arch/x86/model/statedata.c`、`arch/x86/64/model/statedata.c`。
pub const upstream_rel = "model/statedata.c";
pub const upstream_arch_rel = "arch/x86/model/statedata.c";
pub const upstream_arch_64_rel = "arch/x86/64/model/statedata.c";

/// 迁移期占位：对应 `NODE_STATE(ksCurThread)` 的不透明句柄。
pub var ks_cur_thread_tag: u64 = 0;
