//! UEFI / Multiboot2 / FDT 共用的内核初始化；IDT/#PF 探测仅 x86_64（见 `kernel_init_x86.zig`）。
const std = @import("std");
const builtin = @import("builtin");
const kernel_opts = @import("kernel_build_options");
const handoff = @import("handoff.zig");
const boot = @import("../kernel/boot.zig");
const serial_out = @import("../baremetal/serial_plat.zig");

fn hang() noreturn {
    switch (builtin.cpu.arch) {
        .x86_64 => while (true) asm volatile ("hlt"),
        .aarch64 => while (true) asm volatile ("wfe"),
        .riscv64 => while (true) asm volatile ("wfi"),
        .loongarch64 => while (true) asm volatile ("idle 0"),
        else => while (true) {},
    }
}

pub fn kernelInit(h: *const handoff.BootHandoff) void {
    if (h.magic != handoff.magic) {
        serial_out.serialWriteSlice("kernelInit: bad BootHandoff magic\r\n");
        hang();
    }

    boot.runMinimalBootPipeline(h);

    serial_out.serialWriteSlice("kernelInit: BootHandoff ok, regions=");
    var buf: [24]u8 = undefined;
    const n = std.fmt.bufPrint(&buf, "{d}\r\n", .{h.region_count}) catch {
        serial_out.serialWriteSlice("?\r\n");
        hang();
    };
    serial_out.serialWriteSlice(n);

    serial_out.serialWriteSlice("kernel_build_options: arch=");
    serial_out.serialWriteSlice(@tagName(kernel_opts.kernel_arch));
    serial_out.serialWriteSlice(" platform=");
    serial_out.serialWriteSlice(@tagName(kernel_opts.kernel_platform));
    serial_out.serialWriteSlice("\r\n");

    if (comptime builtin.cpu.arch != .x86_64) {
        serial_out.serialWriteSlice("kernelInit: non-x86_64 target, skip IDT / #PF / #DE smoke\r\n");
        hang();
    }

    if (kernel_opts.kernel_arch != .x86_64) {
        serial_out.serialWriteSlice("kernelInit: kernel_arch does not match x86_64 target\r\n");
        hang();
    }

    @import("kernel_init_x86.zig").runX86Smoke(h);
}
