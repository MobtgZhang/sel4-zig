//! QEMU virt IOCSR IPIs, EXTIOI routing and the Loongson PCH PIC.
const Event = @import("../irq_event.zig").Event;
const Controller = @import("../../object/interrupt.zig").Controller;
pub const uart_irq = 2;
fn read(address: u32) u32 {
    return asm volatile ("iocsrrd.w %[v], %[a]"
        : [v] "=r" (-> u32),
        : [a] "r" (address),
        : .{ .memory = true });
}
fn write(address: u32, value: u32) void {
    asm volatile ("iocsrwr.w %[v], %[a]"
        :
        : [v] "r" (value),
          [a] "r" (address),
        : .{ .memory = true });
}
fn pic(offset: usize) *volatile u32 {
    return @ptrFromInt(0x8000000010000000 + offset);
}
pub fn initialize() void {
    pic(0x20).* = 0xffffffff;
    pic(0x24).* = 0xffffffff;
    pic(0x60).* = 0; // Level-triggered sources.
    for (0..32) |i| @as(*volatile u8, @ptrFromInt(0x8000000010000200 + i)).* = @intCast(i);
    // EXTIOI pin zero drives CPU hardware interrupt 2; route to the boot CPU.
    write(0x14c0, 0x01010101);
    write(0x14c4, 0x01010101);
    const bsp = &@import("../../platform/runtime.zig").topology;
    const id = bsp.cpus[bsp.boot_index].hardware_id;
    if (id >= 4) @panic("EXTIOI legacy boot CPU encoding is unsupported");
    const route = @as(u32, 0x01010101) << @as(u5, @intCast(id));
    for (0..64) |i| write(0x1c00 + @as(u32, @intCast(i)) * 4, route);
    for (0..8) |i| write(0x1600 + @as(u32, @intCast(i)) * 4, 0);
    initializeLocal();
}
pub fn initializeLocal() void {
    write(0x1004, 2);
}
pub fn sendIpi(id: u64) void {
    asm volatile ("dbar 0" ::: .{ .memory = true });
    write(0x1040, 0x80000001 | @as(u32, @intCast(id << 16)));
}
pub fn claim(estat: u64) Event {
    if (estat & (1 << 12) != 0) {
        write(0x100c, 2);
        return .ipi;
    }
    if (estat & (1 << 11) != 0) {
        @import("timer.zig").acknowledge();
        return .timer;
    }
    if (estat & (1 << 2) != 0) {
        for (0..8) |i| {
            const bits = read(0x1800 + @as(u32, @intCast(i)) * 4);
            if (bits != 0) return .{ .device = @intCast(i * 32 + @ctz(bits)) };
        }
    }
    return .spurious;
}
fn mask(_: ?*anyopaque, irq: u16, masked: bool) void {
    if (irq >= 32) return;
    const bit = @as(u32, 1) << @as(u5, @intCast(irq));
    if (masked) {
        pic(0x20).* |= bit;
        write(0x1600, read(0x1600) & ~bit);
    } else {
        write(0x1600, read(0x1600) | bit);
        pic(0x20).* &= ~bit;
    }
    asm volatile ("dbar 0" ::: .{ .memory = true });
}
fn complete(_: ?*anyopaque, irq: u16) void {
    write(0x1800 + @as(u32, irq / 32) * 4, @as(u32, 1) << @as(u5, @truncate(irq)));
}
fn valid(irq: u16) bool {
    return irq < 32;
}
pub const controller: Controller = .{ .valid = valid, .context = null, .mask = mask, .acknowledge = complete };

pub fn probeSource(enabled: bool) void {
    const enable: *volatile u8 = @ptrFromInt(0x800000001fe001e0 + 1);
    enable.* = if (enabled) 2 else 0;
}
