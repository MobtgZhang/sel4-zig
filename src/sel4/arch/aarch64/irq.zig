//! QEMU virt GICv2: Group 0 interrupts, SGI 1 rescheduling and device IRQs.
const Event = @import("../irq_event.zig").Event;
const Controller = @import("../../object/interrupt.zig").Controller;
const d = 0x08000000;
const c = 0x08010000;
fn reg(base: usize, offset: usize) *volatile u32 {
    return @ptrFromInt(base + offset);
}
pub const uart_irq = 33;
pub fn initialize() void {
    const banks = (reg(d, 4).* & 31) + 1;
    for (0..banks) |i| {
        reg(d, 0x180 + i * 4).* = 0xffffffff;
        reg(d, 0x80 + i * 4).* = 0;
    }
    reg(d, 0).* = 1;
    initializeLocal();
}
pub fn initializeLocal() void {
    reg(d, 0x80).* = 0;
    reg(d, 0x100).* = 1 << 1;
    reg(c, 4).* = 0xff;
    reg(c, 8).* = 0;
    reg(c, 0).* = 1;
}
pub fn sendIpi(id: u64) void {
    if (id >= 8) @panic("GICv2 target exceeds eight CPUs");
    asm volatile ("dsb ishst" ::: .{ .memory = true });
    reg(d, 0xf00).* = (@as(u32, 1) << @as(u5, @intCast(16 + id))) | 1;
}
pub fn claim() Event {
    const token = reg(c, 0xc).*;
    const irq: u16 = @intCast(token & 0x3ff);
    if (irq >= 1020) return .spurious;
    if (irq == 27) {
        @import("timer.zig").rearm();
        reg(c, 0x10).* = token;
        return .timer;
    }
    if (irq == 1) {
        reg(c, 0x10).* = token;
        return .ipi;
    }
    return .{ .device = irq };
}
fn mask(_: ?*anyopaque, irq: u16, masked: bool) void {
    const offset: usize = if (masked) 0x180 else 0x100;
    if (!masked) {
        @as(*volatile u8, @ptrFromInt(d + 0x400 + @as(usize, irq))).* = 0x80;
        if (irq >= 32) {
            const id = @import("../../platform/runtime.zig").topology.cpus[@import("../../platform/runtime.zig").topology.boot_index].hardware_id;
            @as(*volatile u8, @ptrFromInt(d + 0x800 + @as(usize, irq))).* = @as(u8, 1) << @as(u3, @intCast(id));
        }
    }
    reg(d, offset + @as(usize, irq / 32) * 4).* = @as(u32, 1) << @as(u5, @truncate(irq));
    asm volatile ("dsb sy" ::: .{ .memory = true });
}
fn complete(_: ?*anyopaque, irq: u16) void {
    reg(c, 0x10).* = irq;
}
fn valid(irq: u16) bool {
    return irq >= 32 and irq < 256;
}
pub const controller: Controller = .{ .valid = valid, .context = null, .mask = mask, .acknowledge = complete };

pub fn probeSource(enabled: bool) void {
    reg(0x09000000, 0x38).* = if (enabled) 1 << 5 else 0;
    if (enabled) reg(0x09000000, 0).* = 0;
}
