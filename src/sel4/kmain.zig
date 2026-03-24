//! 迁移计划阶段 1–2：Multiboot2 / FDT / UEFI 共用的 Zig 根。
const std = @import("std");
const builtin = @import("builtin");
const handoff = @import("boot/handoff.zig");
const fdt = @import("boot/fdt.zig");
const kernel_init = @import("boot/kernel_init.zig");
const serial = @import("baremetal/serial_plat.zig");
const kb = @import("kernel_build_options");

pub const panic = barePanic;

fn barePanic(msg: []const u8, st: ?*std.builtin.StackTrace, ra: ?usize) noreturn {
    _ = st;
    _ = ra;
    serial.serialWriteSlice("PANIC: ");
    serial.serialWriteSlice(msg);
    serial.serialWriteSlice("\r\n");
    hang();
}

fn hang() noreturn {
    switch (builtin.cpu.arch) {
        .x86_64 => while (true) asm volatile ("hlt"),
        .aarch64 => while (true) asm volatile ("wfe"),
        .riscv64 => while (true) asm volatile ("wfi"),
        .loongarch64 => while (true) asm volatile ("idle 0"),
        else => while (true) {},
    }
}

/// x86 Multiboot2：`ebx` 物理指针，由 `multiboot2_longmode.S` 写入。
export var mb2_saved: u64 = 0;

export fn onDivideError() callconv(.c) void {
    serial.serialWriteSlice("#DE: divide error (ISR)\r\n");
}

export fn onPageFaultRegs(error_code: u64, cr2: u64) callconv(.c) noreturn {
    @import("api/faults.zig").reportPageFault(error_code, cr2);
}

/// `arg == 0`（仅 x86）：Multiboot2/PVH，从 `mb2_saved` 构造 handoff。
/// `arg != 0`：`BootHandoff*` 物理地址（UEFI），或 DTB 物理指针（AArch64/RISC-V/LoongArch 裸机）。
export fn kmain(arg: u64) callconv(.c) void {
    serial.serialWriteSlice("seL4-Zig bare kernel: kmain\r\n");

    if (kb.kernel_arch == .x86_64) {
        if (arg != 0) {
            const hp: *const handoff.BootHandoff = @ptrFromInt(arg);
            kernel_init.kernelInit(hp);
            hang();
        }
        var hb: handoff.BootHandoff = undefined;
        handoff.fillFromMultiboot2(&hb, mb2_saved);
        kernel_init.kernelInit(&hb);
        hang();
    }

    var hb: handoff.BootHandoff = undefined;
    fdt.fillFromFdt(&hb, arg);
    kernel_init.kernelInit(&hb);
    hang();
}
