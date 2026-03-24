//! 阶段三优先级 1：TLB 刷新（对应 x86 `invlpg` 等；完整策略见 `vspace.c` 镜像）。
const builtin = @import("builtin");

comptime {
    if (builtin.cpu.arch != .x86_64) @compileError("tlb.zig requires x86_64");
}

pub inline fn invlpg(addr: usize) void {
    asm volatile ("invlpg (%[a])"
        :
        : [a] "r" (addr),
        : .{ .memory = true });
}
