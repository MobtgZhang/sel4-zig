//! 阶段三优先级 4：idea1 中的 `ipc.c` 在现网 seL4 中主要由 `api/syscall.c` + 各 `object/*.c` 承担。
pub const upstream_rel = "api/syscall.c";

pub const syscall_mod = @import("syscall.zig");
pub const dispatch = @import("../kernel/ipc_dispatch.zig");
