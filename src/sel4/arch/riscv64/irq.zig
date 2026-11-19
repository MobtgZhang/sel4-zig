//! QEMU virt PLIC supervisor contexts and SBI software IPIs.
const Event = @import("../irq_event.zig").Event;
const Controller = @import("../../object/interrupt.zig").Controller;
const base = 0x0c000000;
pub const uart_irq = 10;
fn reg(offset: usize) *volatile u32 {
    return @ptrFromInt(base + offset);
}
fn context() usize {
    return @intCast(@import("backend.zig").currentHardwareId() * 2 + 1);
}
pub fn initialize() void {
    reg(uart_irq * 4).* = 1;
    initializeLocal();
}
pub fn initializeLocal() void {
    reg(0x200000 + context() * 4096).* = 0;
    asm volatile ("csrs sie, %[mask]"
        :
        : [mask] "r" (@as(u64, (1 << 1) | (1 << 9))),
        : .{ .memory = true });
}
pub fn sendIpi(id: u64) void {
    const result = asm volatile ("ecall"
        : [err] "={a0}" (-> isize),
        : [mask] "{a0}" (@as(u64, 1)),
          [base] "{a1}" (id),
          [fid] "{a6}" (@as(u64, 0)),
          [eid] "{a7}" (@as(u64, 0x735049)),
        : .{ .a1 = true, .memory = true });
    if (result != 0) @panic("SBI send_ipi failed");
}
pub fn claim(cause: u64) Event {
    return switch (cause & 0x7fffffffffffffff) {
        1 => blk: {
            asm volatile ("csrci sip, 2" ::: .{ .memory = true });
            break :blk .ipi;
        },
        5 => blk: {
            @import("timer.zig").rearm();
            break :blk .timer;
        },
        9 => blk: {
            const irq = reg(0x200004 + context() * 4096).*;
            break :blk if (irq == 0) .spurious else .{ .device = @intCast(irq) };
        },
        else => .spurious,
    };
}
fn mask(_: ?*anyopaque, irq: u16, masked: bool) void {
    const bsp = &@import("../../platform/runtime.zig").topology;
    const target: usize = @intCast(bsp.cpus[bsp.boot_index].hardware_id * 2 + 1);
    const enable = reg(0x2000 + target * 0x80 + @as(usize, irq / 32) * 4);
    const bit = @as(u32, 1) << @as(u5, @truncate(irq));
    if (masked) enable.* &= ~bit else {
        reg(@as(usize, irq) * 4).* = 1;
        enable.* |= bit;
    }
    asm volatile ("fence iorw, iorw" ::: .{ .memory = true });
}
fn complete(_: ?*anyopaque, irq: u16) void {
    reg(0x200004 + context() * 4096).* = irq;
}
fn valid(irq: u16) bool {
    return irq > 0 and irq < 96;
}
pub const controller: Controller = .{ .valid = valid, .context = null, .mask = mask, .acknowledge = complete };

pub fn probeSource(enabled: bool) void {
    const enable: *volatile u8 = @ptrFromInt(0x10000000 + 1);
    enable.* = if (enabled) 2 else 0;
}
