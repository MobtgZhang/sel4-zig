//! Public interfaces for the native IPC implementation.
pub const MessageInfo = @import("message.zig").MessageInfo;
pub const transfer = @import("message.zig").transfer;
pub const dispatch = @import("syscall.zig").dispatch;
