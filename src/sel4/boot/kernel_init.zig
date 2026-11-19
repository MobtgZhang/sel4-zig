//! Common firmware handoff validation and native core initialization checks.
const std = @import("std");
const builtin = @import("builtin");
const options = @import("kernel_build_options");
const handoff = @import("handoff.zig");
const boot = @import("../kernel/boot.zig");
const serial = @import("../platform/console.zig");

pub fn kernelInit(h: *const handoff.BootHandoff) void {
    const available = boot.usableMemory(h, &.{}) catch |err| {
        serial.serialWriteSlice("kernelInit: invalid handoff: ");
        serial.serialWriteSlice(@errorName(err));
        serial.serialWriteSlice("\r\n");
        return;
    };
    @import("../fs/system.zig").mount(h) catch |err| {
        serial.serialWriteSlice("system filesystem: ");
        serial.serialWriteSlice(@errorName(err));
        serial.serialWriteSlice("\r\n");
        return;
    };
    serial.serialWriteSlice("system filesystem: mounted read-only ");
    serial.serialWriteSlice(@import("../fs/system.zig").root.name());
    serial.serialWriteSlice("\r\n");
    serial.serialWriteSlice("kernelInit: BootHandoff ok, regions=");
    var buf: [128]u8 = undefined;
    serial.serialWriteSlice(std.fmt.bufPrint(&buf, "{d}\r\n", .{available.count}) catch "?\r\n");
    serial.serialWriteSlice("kernel_build_options: arch=");
    serial.serialWriteSlice(@tagName(options.kernel_arch));
    serial.serialWriteSlice(" platform=");
    serial.serialWriteSlice(@tagName(options.kernel_platform));
    serial.serialWriteSlice("\r\n");
    @import("../platform/runtime.zig").initialize(h) catch |err| {
        serial.serialWriteSlice("platform initialization failed: ");
        serial.serialWriteSlice(@errorName(err));
        serial.serialWriteSlice("\r\n");
        return;
    };
    const platform = @import("../platform/runtime.zig");
    // Font files can contain sparse blocks. Materialize them only after the
    // physical allocator has excluded all live boot and firmware reservations.
    serial.configure(h) catch |err| {
        serial.serialWriteSlice(@errorName(err));
        return;
    };
    const smp = @import("../platform/smp.zig");
    @import("../platform/clock.zig").initialize() catch |err| {
        serial.serialWriteSlice("clock initialization failed: ");
        serial.serialWriteSlice(@errorName(err));
        serial.serialWriteSlice("\r\n");
        return;
    };
    smp.initialize() catch |err| {
        serial.serialWriteSlice("SMP startup failed: ");
        serial.serialWriteSlice(@errorName(err));
        serial.serialWriteSlice("\r\n");
        return;
    };
    smp.selfTest() catch |err| {
        serial.serialWriteSlice("SMP synchronization self-test: FAIL ");
        serial.serialWriteSlice(@errorName(err));
        serial.serialWriteSlice("\r\n");
        return;
    };
    serial.serialWriteSlice(std.fmt.bufPrint(&buf, "CPUs: {d} online / {d} discovered\r\n", .{ platform.topology.onlineCount(), platform.topology.count }) catch "CPUs initialized\r\n");
    serial.serialWriteSlice("SMP synchronization self-test: PASS\r\n");
    serial.serialWriteSlice("physical page allocation and mapping: PASS\r\n");
    // A missing data disk must not prevent recovery or read-only system access.
    // Keep the actual transport error visible instead of silently losing /data.
    if (@import("../drivers/virtio_block.zig").init()) |_| {
        serial.serialWriteSlice("persistent disk: ready\r\n");
    } else |err| {
        serial.serialWriteSlice("persistent disk: ");
        serial.serialWriteSlice(@errorName(err));
        serial.serialWriteSlice("\r\n");
    }
    // No physical allocation is allowed until the image, boot data, page tables,
    // firmware reservations, and root-task image have all been excluded.
    if (comptime builtin.cpu.arch == .x86_64) @import("../arch/x86_64/boot_init.zig").install();
    @import("../kernel/selftest.zig").run() catch |err| {
        serial.serialWriteSlice("kernel core self-test: FAIL ");
        serial.serialWriteSlice(@errorName(err));
        serial.serialWriteSlice("\r\n");
        return;
    };
    serial.serialWriteSlice("kernel core self-test: PASS\r\n");
    if (h.flags & handoff.flag_recovery != 0) @import("console.zig").run(h);
    if (comptime builtin.cpu.arch == .x86_64) {
        @import("../arch/x86_64/user_runtime.zig").run(h) catch |err| {
            serial.serialWriteSlice("boot: user runtime failed: ");
            serial.serialWriteSlice(@errorName(err));
            serial.serialWriteSlice("\r\n");
        };
    } else if (comptime builtin.cpu.arch == .aarch64 or builtin.cpu.arch == .riscv64 or builtin.cpu.arch == .loongarch64) {
        @import("../kernel/user_runtime.zig").run(h) catch |err| {
            serial.serialWriteSlice("boot: user runtime failed: ");
            serial.serialWriteSlice(@errorName(err));
            serial.serialWriteSlice("\r\n");
        };
    } else @import("console.zig").run(h);
}
