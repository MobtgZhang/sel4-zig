//! Non-MCS syscall and IPC-buffer bindings. Object invocation coverage is separate.
const builtin = @import("builtin");
const nums = @import("syscall_nums");
const impl = switch (builtin.cpu.arch) {
    .x86_64 => @import("arch/x86_64/syscall.zig"),
    .aarch64 => @import("arch/aarch64/syscall.zig"),
    .riscv64 => @import("arch/riscv64/syscall.zig"),
    .loongarch64 => @import("arch/loongarch64/syscall.zig"),
    else => @compileError("unsupported syscall architecture"),
};
pub const seL4_Word = u64;
pub const seL4_CPtr = u64;
pub const MessageInfo = extern struct {
    words: [1]u64 = .{0},
    pub fn init(message_label: u52, extra: u2, message_length: u7) MessageInfo {
        return .{ .words = .{(@as(u64, message_label) << 12) | (@as(u64, extra) << 7) | message_length} };
    }
    pub fn length(self: MessageInfo) usize {
        return @min(self.words[0] & 127, 120);
    }
    pub fn extraCaps(self: MessageInfo) u2 {
        return @truncate(self.words[0] >> 7);
    }
    pub fn capsUnwrapped(self: MessageInfo) u3 {
        return @truncate(self.words[0] >> 9);
    }
    pub fn label(self: MessageInfo) u52 {
        return @truncate(self.words[0] >> 12);
    }
};
pub const IPCBuffer = extern struct {
    tag: MessageInfo = .{},
    msg: [120]u64 = @splat(0),
    userData: u64 = 0,
    caps_or_badges: [3]u64 = @splat(0),
    receiveCNode: u64 = 0,
    receiveIndex: u64 = 0,
    receiveDepth: u64 = 0,
};
comptime {
    if (@sizeOf(IPCBuffer) != 1024) @compileError("IPCBuffer wire size mismatch");
}
var ipc_buffer: ?*align(1024) IPCBuffer = null;
pub fn seL4_SetIPCBuffer(buffer: *align(1024) IPCBuffer) void {
    ipc_buffer = buffer;
}
pub fn seL4_GetIPCBuffer() *align(1024) IPCBuffer {
    return ipc_buffer.?;
}
pub fn seL4_SetMR(index: usize, value: u64) void {
    ipc_buffer.?.msg[index] = value;
}
pub fn seL4_GetMR(index: usize) u64 {
    return ipc_buffer.?.msg[index];
}
pub fn seL4_SetCap(index: usize, cap: u64) void {
    ipc_buffer.?.caps_or_badges[index] = cap;
}
pub fn seL4_SetCapReceivePath(root: u64, index: u64, depth: u64) void {
    const buffer = ipc_buffer.?;
    buffer.receiveCNode = root;
    buffer.receiveIndex = index;
    buffer.receiveDepth = depth;
}
pub const seL4_SysSend: u64 = @bitCast(nums.seL4_SysSend);
pub const seL4_SysDebugPutChar: u64 = @bitCast(nums.seL4_SysDebugPutChar);
pub inline fn seL4_SendWithMRs(dest: u64, info: MessageInfo, a: u64, b: u64, c: u64, d: u64) void {
    _ = impl.invoke(nums.seL4_SysSend, dest, info.words[0], .{ a, b, c, d });
}
fn invoke(number: i64, dest: u64, info: MessageInfo, badge: ?*u64) MessageInfo {
    const words: [4]u64 = if (ipc_buffer) |buffer| buffer.msg[0..4].* else @splat(0);
    const result = impl.invoke(number, dest, info.words[0], words);
    if (badge) |out| out.* = result.badge;
    if (ipc_buffer) |buffer| {
        buffer.tag.words[0] = result.info;
        buffer.msg[0..4].* = result.words;
    }
    return .{ .words = .{result.info} };
}
pub fn seL4_Send(dest: u64, info: MessageInfo) void {
    _ = invoke(nums.seL4_SysSend, dest, info, null);
}
pub fn seL4_NBSend(dest: u64, info: MessageInfo) void {
    _ = invoke(nums.seL4_SysNBSend, dest, info, null);
}
pub fn seL4_Call(dest: u64, info: MessageInfo) MessageInfo {
    return invoke(nums.seL4_SysCall, dest, info, null);
}
pub fn seL4_Recv(src: u64, badge: ?*u64) MessageInfo {
    return invoke(nums.seL4_SysRecv, src, .{}, badge);
}
pub fn seL4_NBRecv(src: u64, badge: ?*u64) MessageInfo {
    return invoke(nums.seL4_SysNBRecv, src, .{}, badge);
}
pub fn seL4_Reply(info: MessageInfo) void {
    _ = invoke(nums.seL4_SysReply, 0, info, null);
}
pub fn seL4_ReplyRecv(src: u64, info: MessageInfo, badge: ?*u64) MessageInfo {
    return invoke(nums.seL4_SysReplyRecv, src, info, badge);
}
pub fn seL4_Yield() void {
    _ = impl.invoke(nums.seL4_SysYield, 0, 0, @splat(0));
}
pub fn seL4_Signal(dest: u64) void {
    seL4_Send(dest, .{});
}
pub fn seL4_Wait(src: u64, badge: ?*u64) void {
    _ = seL4_Recv(src, badge);
}
pub fn seL4_Poll(src: u64, badge: ?*u64) void {
    _ = seL4_NBRecv(src, badge);
}
pub fn seL4_DebugPutChar(c: u8) void {
    _ = impl.invoke(nums.seL4_SysDebugPutChar, c, 0, @splat(0));
}
/// Exposed for ABI and unknown-syscall fault tests.
pub const raw = impl.invoke;

// Keep wire marshalling separate from architecture-specific syscall assembly.
pub const seL4_CNode_Copy = @import("invocation.zig").seL4_CNode_Copy;
pub const seL4_CNode_Mint = @import("invocation.zig").seL4_CNode_Mint;
pub const seL4_CNode_Move = @import("invocation.zig").seL4_CNode_Move;
pub const seL4_CNode_Mutate = @import("invocation.zig").seL4_CNode_Mutate;
pub const seL4_CNode_Rotate = @import("invocation.zig").seL4_CNode_Rotate;
pub const seL4_CNode_Revoke = @import("invocation.zig").seL4_CNode_Revoke;
pub const seL4_CNode_Delete = @import("invocation.zig").seL4_CNode_Delete;
pub const seL4_CNode_CancelBadgedSends = @import("invocation.zig").seL4_CNode_CancelBadgedSends;
pub const seL4_CNode_SaveCaller = @import("invocation.zig").seL4_CNode_SaveCaller;
pub const seL4_TCB_SetPriority = @import("invocation.zig").seL4_TCB_SetPriority;
pub const seL4_TCB_SetMCPriority = @import("invocation.zig").seL4_TCB_SetMCPriority;
pub const seL4_TCB_SetSchedParams = @import("invocation.zig").seL4_TCB_SetSchedParams;
pub const seL4_TCB_Suspend = @import("invocation.zig").seL4_TCB_Suspend;
pub const seL4_TCB_Resume = @import("invocation.zig").seL4_TCB_Resume;
pub const seL4_TCB_SetAffinity = @import("invocation.zig").seL4_TCB_SetAffinity;
pub const seL4_TCB_BindNotification = @import("invocation.zig").seL4_TCB_BindNotification;
pub const seL4_TCB_UnbindNotification = @import("invocation.zig").seL4_TCB_UnbindNotification;
pub const seL4_Untyped_Retype = @import("invocation.zig").seL4_Untyped_Retype;
pub const seL4_IRQControl_Get = @import("invocation.zig").seL4_IRQControl_Get;
pub const seL4_IRQHandler_Ack = @import("invocation.zig").seL4_IRQHandler_Ack;
pub const seL4_IRQHandler_SetNotification = @import("invocation.zig").seL4_IRQHandler_SetNotification;
pub const seL4_IRQHandler_Clear = @import("invocation.zig").seL4_IRQHandler_Clear;
