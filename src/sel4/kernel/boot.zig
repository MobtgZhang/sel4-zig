//! 对照 `seL4/src/kernel/boot.c`、`arch/x86/kernel/boot.c`、`arch/x86/kernel/boot_sys.c` 的渐进迁移入口。
const std = @import("std");

pub const upstream_rel = "kernel/boot.c";
pub const upstream_arch_boot_rel = "arch/x86/kernel/boot.c";
pub const upstream_boot_sys_rel = "arch/x86/kernel/boot_sys.c";

const handoff = @import("../boot/handoff.zig");
const serial = @import("../baremetal/serial_plat.zig");
const boot_mem = @import("boot_mem.zig");
const hybrid = @import("../hybrid/boot_bridge.zig");

/// 与 `arch/x86/kernel/boot_sys.c` 中早期阶段相当：校验 handoff、演练保留区合并（`boot_mem`），再进入历史 smoke 桩。
pub fn runMinimalBootPipeline(h: *const handoff.BootHandoff) void {
    if (h.magic != handoff.magic) return;

    serial.serialWriteSlice("boot: arch_boot + boot_sys (minimal Zig)\r\n");

    var buf: [boot_mem.max_reserved]boot_mem.PRegion = undefined;
    var n: usize = 0;
    _ = boot_mem.reserveRegion(&buf, &n, .{ .start = 0x1000, .end = 0x2000 });
    _ = boot_mem.reserveRegion(&buf, &n, .{ .start = 0x2000, .end = 0x3000 });
    serial.serialWriteSlice("boot: merge_regions demo n=");
    var tmp1: [16]u8 = undefined;
    const line = std.fmt.bufPrint(&tmp1, "{d}\r\n", .{n}) catch "?";
    serial.serialWriteSlice(line);

    serial.serialWriteSlice("boot: handoff region_count=");
    var tmp2: [16]u8 = undefined;
    const line2 = std.fmt.bufPrint(&tmp2, "{d}\r\n", .{h.region_count}) catch "?";
    serial.serialWriteSlice(line2);
}

/// 主机单测与兼容：仍调用纯 Zig 桩。
pub fn zigSmokeBootStub() void {
    hybrid.callBootStub();
}
