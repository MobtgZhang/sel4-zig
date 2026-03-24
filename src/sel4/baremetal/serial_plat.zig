//! 按 `kernel_build_options` 选择早期调试串口（MMIO 轮询）。
const kb = @import("kernel_build_options");
const pa64 = @import("../plat/qemu_aarch64_virt.zig");
const prv = @import("../plat/qemu_riscv64_virt.zig");

fn com1_putc(c: u8) void {
    switch (comptime @import("builtin").cpu.arch) {
        .x86_64 => @import("serial_com1.zig").serialWriteSlice(&.{c}),
        else => {},
    }
}

fn pl011_putc(c: u8) void {
    const base: usize = pa64.uart0_mmio_base;
    const fr = @as(*volatile u32, @ptrFromInt(base + 0x18));
    const dr = @as(*volatile u32, @ptrFromInt(base));
    while ((fr.* & (1 << 5)) != 0) {}
    dr.* = @intCast(c);
}

fn ns16550_putc(c: u8) void {
    const base: usize = prv.uart0_mmio_base;
    const lsr = @as(*volatile u8, @ptrFromInt(base + 0x5));
    const thr = @as(*volatile u8, @ptrFromInt(base));
    while ((lsr.* & 0x20) == 0) {}
    thr.* = c;
}

pub fn serialPutChar(c: u8) void {
    switch (kb.kernel_platform) {
        .pc99 => com1_putc(c),
        .qemu_aarch64_virt => pl011_putc(c),
        .qemu_riscv64_virt => ns16550_putc(c),
        .qemu_loongarch64_virt => {},
    }
}

pub fn serialWriteSlice(s: []const u8) void {
    for (s) |c| serialPutChar(c);
}
