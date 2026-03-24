//! 阶段三优先级 1：原 `machine.c` 在现网 seL4 x86 上拆在 `machine/*.c`；此处用 Zig 实现**无状态寄存器原语**。
//! 复杂设备/平台逻辑仍以镜像 C 为准：`seL4/src/arch/x86/machine/`。
const builtin = @import("builtin");

comptime {
    if (builtin.cpu.arch != .x86_64) @compileError("seL4-Zig x86_64 machine.zig requires x86_64");
}

pub fn rdmsr(msr: u32) u64 {
    var lo: u32 = undefined;
    var hi: u32 = undefined;
    asm volatile ("rdmsr"
        : [lo] "={eax}" (lo),
          [hi] "={edx}" (hi),
        : [ecx] "{ecx}" (msr),
        : .{ .memory = true });
    return (@as(u64, hi) << 32) | lo;
}

pub fn wrmsr(msr: u32, value: u64) void {
    const lo: u32 = @truncate(value);
    const hi: u32 = @truncate(value >> 32);
    asm volatile ("wrmsr"
        :
        : [ecx] "{ecx}" (msr),
          [eax] "{eax}" (lo),
          [edx] "{edx}" (hi),
        : .{ .memory = true });
}

pub fn cpuid(leaf: u32, subleaf: u32) struct { eax: u32, ebx: u32, ecx: u32, edx: u32 } {
    var eax: u32 = undefined;
    var ebx: u32 = undefined;
    var ecx: u32 = undefined;
    var edx: u32 = undefined;
    asm volatile ("cpuid"
        : [eax] "={eax}" (eax),
          [ebx] "={ebx}" (ebx),
          [ecx] "={ecx}" (ecx),
          [edx] "={edx}" (edx),
        : [leaf] "{eax}" (leaf),
          [subleaf] "{ecx}" (subleaf),
        : .{ .memory = true });
    return .{ .eax = eax, .ebx = ebx, .ecx = ecx, .edx = edx };
}

pub fn readCr0() u64 {
    return asm volatile ("mov %%cr0, %[out]"
        : [out] "=r" (-> u64),
    );
}

pub fn readCr3() u64 {
    return asm volatile ("mov %%cr3, %[out]"
        : [out] "=r" (-> u64),
    );
}

pub fn writeCr3(value: u64) void {
    asm volatile ("mov %[v], %%cr3"
        :
        : [v] "r" (value),
        : .{ .memory = true }
    );
}
