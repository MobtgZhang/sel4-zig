//! Initialize shared hardware resources only after boot reservations are complete.
const builtin = @import("builtin");
const std = @import("std");
const handoff = @import("../boot/handoff.zig");
const memory = @import("memory.zig");
const cpu = @import("cpu.zig");
const boot = @import("../kernel/boot.zig");
pub var pages: memory.PagePool = .{};
pub var topology: cpu.Topology = .{};
extern const __kernel_start: u8;
extern const __kernel_end: u8;
pub fn initialize(h: *const handoff.BootHandoff) !void {
    const mask: u64 = if (comptime builtin.cpu.arch == .loongarch64) 0x0000ffffffffffff else std.math.maxInt(u64);
    const start = @intFromPtr(&__kernel_start) & mask;
    const end = @intFromPtr(&__kernel_end) & mask;
    var available = try boot.usableMemory(h, &.{.{ .start = start, .end = end }});
    // Low bootstrap tables, firmware scratch structures and trampolines are live.
    if (comptime builtin.cpu.arch == .x86_64 or builtin.cpu.arch == .loongarch64) try available.subtract(.{ .start = 0, .end = 0x100000 });
    if (h.framebuffer.address != 0) {
        try h.framebuffer.validate();
        try available.subtract(.{ .start = h.framebuffer.address, .end = h.framebuffer.address + h.framebuffer.byte_size });
    }
    // Early direct mappings cover only 32-bit physical addresses on x86.
    // Other RAM stays unavailable until a full kernel mapping is installed.
    if (comptime builtin.cpu.arch == .x86_64) try available.subtract(.{ .start = 0x1_0000_0000, .end = std.math.maxInt(u64) });
    pages = try memory.PagePool.init(available);
    topology = try cpu.Topology.init(h, cpu.currentHardwareId());
    const lease = try pages.allocate();
    const probe: [*]volatile u64 = @ptrFromInt(memory.directAddress(lease.address));
    for (0..512) |i| probe[i] = 0x5041474500000000 | i;
    for (0..512) |i| if (probe[i] != 0x5041474500000000 | i) return error.PhysicalMemoryFailed;
    for (0..512) |i| probe[i] = 0;
    try pages.release(lease);
}
