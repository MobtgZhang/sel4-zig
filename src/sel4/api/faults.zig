//! 镜像：`seL4/src/api/faults.c`；此处为裸机陷阱桩与串口诊断。
//! 上游：`seL4/src/api/faults.c`
const builtin = @import("builtin");
const serial = @import("../baremetal/serial_plat.zig");

pub const upstream_rel = "api/faults.c";

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
    serial.serialWriteSlice(hexU64(error_code));
    serial.serialWriteSlice(" cr2=0x");
    serial.serialWriteSlice(hexU64(cr2));
    serial.serialWriteSlice("\r\n");
    hangAfterFault();
}

fn hexU64(v: u64) []const u8 {
    const alphabet = "0123456789abcdef";
    var buf: [16]u8 = undefined;
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
