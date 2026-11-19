//! COM1 serial output shared by the boot entry and exception diagnostics.
fn outb(port: u16, value: u8) void {
    asm volatile ("outb %[v], %[p]"
        :
        : [v] "{al}" (value),
          [p] "{dx}" (port),
        : .{ .memory = true });
}

fn inb(port: u16) u8 {
    return asm volatile ("inb %[p], %[v]"
        : [v] "={al}" (-> u8),
        : [p] "{dx}" (port),
        : .{ .memory = true });
}

fn serialWriteByte(byte: u8) void {
    const com1_data: u16 = 0x3F8;
    const com1_lsr: u16 = 0x3FD;
    var spin: u32 = 0;
    while (spin < 1_000_000 and (inb(com1_lsr) & 0x20) == 0) {
        spin += 1;
    }
    outb(com1_data, byte);
}

pub fn serialWriteSlice(msg: []const u8) void {
    for (msg) |c| serialWriteByte(c);
}

/// Configure COM1 for 115200 baud, 8 data bits, no parity, one stop bit.
pub fn init() void {
    outb(0x3f9, 0);
    outb(0x3fb, 0x80);
    outb(0x3f8, 1);
    outb(0x3f9, 0);
    outb(0x3fb, 3);
    outb(0x3fa, 0xc7);
    outb(0x3fc, 3);
}
pub fn serialReadByte() ?u8 {
    if (inb(0x3fd) & 1 == 0) return null;
    return inb(0x3f8);
}
