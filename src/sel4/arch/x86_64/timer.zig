//! QEMU PC timer: 8254 channel zero routed through the 8259 interrupt controllers.
fn out(port: u16, value: u8) void {
    asm volatile ("outb %[value], %[port]"
        :
        : [value] "{al}" (value),
          [port] "{dx}" (port),
        : .{ .memory = true });
}
pub fn initialize() void {
    // Remap both controllers before exposing user IF; mask every device except PIT.
    out(0x20, 0x11);
    out(0xa0, 0x11);
    out(0x21, 0x20);
    out(0xa1, 0x28);
    out(0x21, 4);
    out(0xa1, 2);
    out(0x21, 1);
    out(0xa1, 1);
    out(0x21, 0xfe);
    out(0xa1, 0xff);
    out(0x43, 0x36);
    const divisor: u16 = 11932;
    out(0x40, @truncate(divisor));
    out(0x40, @truncate(divisor >> 8));
}
pub fn acknowledge() void {
    out(0x20, 0x20);
}

fn apic(offset: usize) *volatile u32 {
    return @ptrFromInt((@import("machine.zig").rdmsr(0x1b) & 0xfffff000) + offset);
}
/// QEMU's local APIC timer clock is 1 GHz; divide by 16 for a 10 ms slice.
pub fn initializeLocal() void {
    apic(0xf0).* = 0x1ff;
    apic(0x80).* = 0;
    apic(0x3e0).* = 3;
    apic(0x320).* = 48 | (1 << 17);
    apic(0x380).* = 625_000;
}
pub fn acknowledgeLocal() void {
    apic(0xb0).* = 0;
}
