//! INIT/SIPI startup with a position-independent real-mode trampoline at 0x8000.
const std = @import("std");
const machine = @import("machine.zig");
extern const ap_trampoline_start: u8;
extern const ap_trampoline_end: u8;
extern fn secondary_main(usize) callconv(.c) noreturn;
extern var secondary_boot_stacks: [64]usize;
pub const timeout_ticks: u64 = 6_000_000_000;
pub fn ticks() u64 {
    var lo: u32 = undefined;
    var hi: u32 = undefined;
    asm volatile ("rdtsc"
        : [lo] "={eax}" (lo),
          [hi] "={edx}" (hi),
    );
    return (@as(u64, hi) << 32) | lo;
}
fn delay(cycles: u64) void {
    const begin = ticks();
    while (ticks() -% begin < cycles) asm volatile ("pause");
}
fn send(base: usize, id: u32, command: u32) !void {
    const high: *volatile u32 = @ptrFromInt(base + 0x310);
    const low: *volatile u32 = @ptrFromInt(base + 0x300);
    const begin = ticks();
    while (low.* & 0x1000 != 0) if (ticks() -% begin > timeout_ticks) return error.ApicDeliveryTimeout;
    high.* = id << 24;
    low.* = command;
    while (low.* & 0x1000 != 0) if (ticks() -% begin > timeout_ticks) return error.ApicDeliveryTimeout;
}
pub fn start(id: u64, index: usize) !void {
    const apic = machine.rdmsr(0x1b);
    if (id > 255 or apic & (1 << 10) != 0) return error.UnsupportedApicMode;
    const cr3 = machine.readCr3();
    if (cr3 > std.math.maxInt(u32)) return error.UnsupportedBootstrapPageTable;
    const size = @intFromPtr(&ap_trampoline_end) - @intFromPtr(&ap_trampoline_start);
    if (size > 0xe00) return error.TrampolineTooLarge;
    @memcpy(@as([*]u8, @ptrFromInt(0x8000))[0..size], @as([*]const u8, @ptrCast(&ap_trampoline_start))[0..size]);
    const parameters: *[4]u64 = @ptrFromInt(0x8e00);
    parameters.* = .{ cr3, secondary_boot_stacks[index], @intFromPtr(&secondary_main), index };
    asm volatile ("mfence" ::: .{ .memory = true });
    machine.wrmsr(0x1b, apic | (1 << 11));
    const base: usize = @intCast(apic & 0xfffff000);
    const svr: *volatile u32 = @ptrFromInt(base + 0xf0);
    svr.* = svr.* | 0x1ff;
    try send(base, @intCast(id), 0xc500);
    delay(30_000_000);
    try send(base, @intCast(id), 0x8500);
    try send(base, @intCast(id), 0x608);
    delay(1_000_000);
    try send(base, @intCast(id), 0x608);
}
