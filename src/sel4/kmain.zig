//! Common Zig kernel entry for Multiboot2, Xen PVH, FDT, and UEFI.
const std = @import("std");
const builtin = @import("builtin");
const handoff = @import("boot/handoff.zig");
const fdt = @import("boot/fdt.zig");
const kernel_init = @import("boot/kernel_init.zig");
const serial = @import("platform/console.zig");
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

const hang = @import("arch/mod.zig").halt;

/// x86 boot-info pointer preserved by multiboot2_longmode.S.
export var mb2_saved: u64 = 0;
export var pvh_saved: u64 = 0;
export var boot_hardware_id: u64 = 0;

export fn onDivideError() callconv(.c) void {
    serial.serialWriteSlice("#DE: divide error (ISR)\r\n");
}

export fn onPageFaultRegs(error_code: u64, cr2: u64) callconv(.c) noreturn {
    @import("arch/x86_64/exception_report.zig").reportPageFault(error_code, cr2);
}

/// A zero x86 argument selects the Multiboot2/PVH boot-info pointer.
/// Other entries supply a BootHandoff pointer (UEFI) or a device-tree pointer.
export fn kmain(arg: u64) callconv(.c) void {
    serial.init();
    serial.serialWriteSlice("seL4-Zig bare kernel: kmain\r\n");

    if (kb.kernel_arch == .x86_64) {
        if (arg != 0) {
            const hp: *const handoff.BootHandoff = @ptrFromInt(arg);
            kernel_init.kernelInit(hp);
            hang();
        }
        var hb: handoff.BootHandoff = undefined;
        const result = if (pvh_saved != 0) handoff.fillFromPvh(&hb, mb2_saved) else handoff.fillFromMultiboot2(&hb, mb2_saved);
        result catch |err| {
            serial.serialWriteSlice("boot: invalid x86 memory map: ");
            serial.serialWriteSlice(@errorName(err));
            serial.serialWriteSlice("\r\n");
            hang();
        };
        kernel_init.kernelInit(&hb);
        hang();
    }

    var hb: handoff.BootHandoff = undefined;
    const parsed = if (comptime builtin.cpu.arch == .loongarch64) @import("arch/loongarch64/boot.zig").fill(&hb, arg) else fdt.fillFromFdt(&hb, arg);
    parsed catch |err| {
        serial.serialWriteSlice("boot: invalid device tree: ");
        serial.serialWriteSlice(@errorName(err));
        serial.serialWriteSlice("\r\n");
        hang();
    };
    kernel_init.kernelInit(&hb);
    hang();
}

/// Firmware uses this explicit entry, independently of raw boot protocols.
export fn uefi_kmain(address: u64) callconv(.c) noreturn {
    serial.init();
    serial.serialWriteSlice("seL4-Zig UEFI kernel: kmain\r\n");
    const h: *const handoff.BootHandoff = @ptrFromInt(address);
    kernel_init.kernelInit(h);
    hang();
}
