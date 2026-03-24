//! 与上游 `libsel4/arch_include/riscv/sel4/arch/syscalls.h` 中 `riscv_sys_send` / `riscv_sys_send_recv` 一致。
const builtin = @import("builtin");
const nums = @import("syscall_nums");

comptime {
    if (builtin.cpu.arch != .riscv64) @compileError("syscall_riscv64.zig is riscv64 only");
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
    var d = dest;
    var info = msg_info.words[0];
    var m0 = mr0;
    var m1 = mr1;
    var m2 = mr2;
    var m3 = mr3;
    asm volatile ("ecall"
        : [d] "+{a0}" (d),
          [i] "+{a1}" (info),
          [m0] "+{a2}" (m0),
          [m1] "+{a3}" (m1),
          [m2] "+{a4}" (m2),
          [m3] "+{a5}" (m3),
        : [sc] "{a7}" (seL4_SysSend),
    );
}

pub inline fn seL4_DebugPutChar(c: u8) void {
    var d: seL4_Word = c;
    var info: seL4_Word = 0;
    var m0: seL4_Word = 0;
    var m1: seL4_Word = 0;
    var m2: seL4_Word = 0;
    var m3: seL4_Word = 0;
    asm volatile ("ecall"
        : [m0] "+{a2}" (m0),
          [m1] "+{a3}" (m1),
          [m2] "+{a4}" (m2),
          [m3] "+{a5}" (m3),
          [info] "+{a1}" (info),
          [d] "+{a0}" (d),
        : [sc] "{a7}" (seL4_SysDebugPutChar),
        : .{ .memory = true });
}
