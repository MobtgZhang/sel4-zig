//! QEMU virt GICv2 and the architected virtual timer (PPI 27).
fn reg(base: usize, offset: usize) *volatile u32 {
    return @ptrFromInt(base + offset);
}
const distributor = 0x08000000;
const interface = 0x08010000;
var interval: u64 = 0;
pub fn initialize() void {
    const frequency = asm volatile ("mrs %[v], cntfrq_el0"
        : [v] "=r" (-> u64),
    );
    interval = @max(1, frequency / 100);
    initializeLocal();
}
pub fn initializeLocal() void {
    // QEMU virt uses the Group 0 view when the security extension is disabled.
    reg(distributor, 0x80).* = 0;
    const priority: *volatile u8 = @ptrFromInt(distributor + 0x400 + 27);
    priority.* = 0x80;
    reg(distributor, 0x100).* = 1 << 27;
    reg(distributor, 0).* = 1;
    reg(interface, 4).* = 0xff;
    reg(interface, 8).* = 0;
    reg(interface, 0).* = 1;
    rearm();
}
pub fn rearm() void {
    asm volatile ("msr cntv_tval_el0, %[v]; msr cntv_ctl_el0, %[enable]; isb"
        :
        : [v] "r" (interval),
          [enable] "r" (@as(u64, 1)),
        : .{ .memory = true });
}
pub fn claim() ?u16 {
    const token = reg(interface, 0xc).*;
    const irq: u16 = @intCast(token & 0x3ff);
    if (irq >= 1020) return null;
    if (irq == 27) rearm();
    // Only the timer is enabled. Keep unexpected sources masked before EOI.
    if (irq != 27) reg(distributor, 0x180 + @as(usize, irq / 32) * 4).* = @as(u32, 1) << @as(u5, @truncate(irq));
    reg(interface, 0x10).* = token;
    asm volatile ("dsb sy; isb" ::: .{ .memory = true });
    return irq;
}
