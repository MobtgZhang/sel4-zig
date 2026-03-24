//! 非 x86_64 主机：`seL4_Send` 等为占位（不执行 syscall），便于 `zig build test` 跨架构通过。
const builtin = @import("builtin");
const nums = @import("syscall_nums");

comptime {
    if (builtin.cpu.arch == .x86_64) @compileError("use syscall_x86_64.zig");
}

pub const seL4_Word = usize;
pub const seL4_CPtr = seL4_Word;

pub const MessageInfo = extern struct {
    words: [1]seL4_Word = .{0},
};

pub const seL4_SysSend: seL4_Word = @bitCast(nums.seL4_SysSend);
pub const seL4_SysDebugPutChar: seL4_Word = @bitCast(nums.seL4_SysDebugPutChar);

pub inline fn seL4_Send(dest: seL4_CPtr, msg_info: MessageInfo) void {
    seL4_SendWithMRs(dest, msg_info, 0, 0, 0, 0);
}

pub inline fn seL4_SendWithMRs(
    dest: seL4_CPtr,
    msg_info: MessageInfo,
    mr0: seL4_Word,
    mr1: seL4_Word,
    mr2: seL4_Word,
    mr3: seL4_Word,
) void {
    _ = .{ dest, msg_info, mr0, mr1, mr2, mr3 };
}
