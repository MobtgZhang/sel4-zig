//! Safe fallback until architecture fastpath preconditions are implemented.
//! A fastpath must preserve exactly the same observable IPC semantics.
pub const upstream_rel = "fastpath/fastpath.c";
pub const dispatch = @import("../api/syscall.zig").dispatch;
