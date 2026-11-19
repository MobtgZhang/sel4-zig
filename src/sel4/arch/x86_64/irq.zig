//! Remapped 8259 device IRQs and xAPIC fixed-delivery reschedule IPIs.
const Controller = @import("../../object/interrupt.zig").Controller;
const io = @import("../../platform/io.zig");
const machine = @import("machine.zig");
pub const uart_irq = 4;
pub fn initialize() void {
    initializeLocal();
}
pub fn initializeLocal() void {
    apic(0xf0).* = 0x1ff;
    apic(0x80).* = 0;
}
fn apic(offset: usize) *volatile u32 {
    return @ptrFromInt((machine.rdmsr(0x1b) & 0xfffff000) + offset);
}
pub fn sendIpi(id: u64) void {
    const start = @import("smp.zig").ticks();
    while (apic(0x300).* & 0x1000 != 0) {
        if (@import("smp.zig").ticks() -% start > @import("smp.zig").timeout_ticks) @panic("IPI delivery stalled");
        asm volatile ("pause");
    }
    apic(0x310).* = @as(u32, @intCast(id)) << 24;
    apic(0x300).* = 240;
}
pub fn acknowledgeIpi() void {
    apic(0xb0).* = 0;
}
fn mask(_: ?*anyopaque, irq: u16, masked: bool) void {
    if (irq >= 16) return;
    const port: u16 = if (irq < 8) 0x21 else 0xa1;
    const bit = @as(u8, 1) << @as(u3, @truncate(irq));
    const old = io.in8(port);
    io.out8(port, if (masked) old | bit else old & ~bit);
    if (!masked and irq >= 8) io.out8(0x21, io.in8(0x21) & ~@as(u8, 4));
}
fn complete(_: ?*anyopaque, irq: u16) void {
    if (irq >= 8) io.out8(0xa0, 0x20);
    io.out8(0x20, 0x20);
}
fn valid(irq: u16) bool {
    return irq > 0 and irq < 16 and irq != 2;
}
pub const controller: Controller = .{ .valid = valid, .context = null, .mask = mask, .acknowledge = complete };

pub fn probeSource(enabled: bool) void {
    io.out8(0x3fc, 0x0b);
    io.out8(0x3f9, if (enabled) 2 else 0);
}
