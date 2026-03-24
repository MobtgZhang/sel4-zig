//! 阶段五 5.2：与上游 `libsel4/.../syscalls_syscall.h` 中 `x64_sys_send` 寄存器约定一致。
const builtin = @import("builtin");
const nums = @import("syscall_nums");

comptime {
    if (builtin.cpu.arch != .x86_64) @compileError("syscall_x86_64.zig is x86_64 only");
}

pub const seL4_Word = usize;
pub const seL4_CPtr = seL4_Word;

pub const MessageInfo = extern struct {
    words: [1]seL4_Word = .{0},
};

/// 与 `kernel/tools/syscall_header_gen.py` 在非 DEBUG/MCS 默认配置下生成的 `SysSend` 一致。
pub const seL4_SysSend: seL4_Word = @bitCast(nums.seL4_SysSend);
pub const seL4_SysDebugPutChar: seL4_Word = @bitCast(nums.seL4_SysDebugPutChar);

/// 对应 `seL4_Send`：`msg0..3` 来自 MR 寄存器镜像（此处由调用方显式传入）。
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
    // 约定与上游 `x64_sys_send` 一致；指令会破坏 %rbx/%rcx/%r11（另见 Linux syscall ABI）。
    asm volatile (
        \\ movq %%rsp, %%rbx
        \\ syscall
        \\ movq %%rbx, %%rsp
        :
        : [sys] "{rdx}" (seL4_SysSend),
          [dest] "{rdi}" (dest),
          [info] "{rsi}" (msg_info.words[0]),
          [m0] "{r10}" (mr0),
          [m1] "{r8}" (mr1),
          [m2] "{r9}" (mr2),
          [m3] "{r15}" (mr3),
    );
}
