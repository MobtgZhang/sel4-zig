//! Early exception diagnostics over the boot serial port.
//! Fatal bootstrap diagnostics; userspace fault IPC is not implemented.
const builtin = @import("builtin");
const serial = @import("../../platform/console.zig");

fn hangAfterFault() noreturn {
    switch (builtin.cpu.arch) {
        .x86_64 => while (true) asm volatile ("hlt"),
        .aarch64 => while (true) asm volatile ("wfe"),
        .riscv64 => while (true) asm volatile ("wfi"),
        .loongarch64 => while (true) asm volatile ("idle 0"),
        else => while (true) {},
    }
}

pub fn reportPageFault(error_code: u64, cr2: u64) noreturn {
    serial.serialWriteSlice("#PF: err=0x");
    var error_buf: [16]u8 = undefined;
    serial.serialWriteSlice(hexU64(&error_buf, error_code));
    serial.serialWriteSlice(" cr2=0x");
    var address_buf: [16]u8 = undefined;
    serial.serialWriteSlice(hexU64(&address_buf, cr2));
    serial.serialWriteSlice("\r\n");
    hangAfterFault();
}

fn hexU64(buf: *[16]u8, v: u64) []const u8 {
    const alphabet = "0123456789abcdef";
    var x = v;
    var i: usize = 16;
    while (i > 0) {
        i -= 1;
        buf[i] = alphabet[@truncate(x & 0xf)];
        x >>= 4;
    }
    return buf[0..16];
}

pub fn reportUnexpectedReturn(which: []const u8) void {
    serial.serialWriteSlice("unexpected return after ");
    serial.serialWriteSlice(which);
    serial.serialWriteSlice("\r\n");
}
