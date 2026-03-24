//! COM1 串口输出（裸机与 `kernel_init` 共用，避免与 `kmain` 循环依赖）。
fn outb(port: u16, value: u8) void {
    asm volatile ("outb %[v], %[p]"
        :
        : [v] "{al}" (value),
          [p] "{dx}" (port),
        : .{ .memory = true }
    );
}

fn inb(port: u16) u8 {
    return asm volatile ("inb %[p], %[v]"
        : [v] "={al}" (-> u8),
        : [p] "{dx}" (port),
        : .{ .memory = true }
    );
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
