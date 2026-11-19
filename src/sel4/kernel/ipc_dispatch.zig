//! Architecture-neutral entry to native kernel syscall dispatch.
pub const upstream_rel = "api/syscall.c";
pub const dispatch = @import("../api/syscall.zig").dispatch;
