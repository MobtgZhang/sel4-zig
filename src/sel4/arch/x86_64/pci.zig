//! PCI configuration mechanism #1 and legacy I/O BAR access.
const io = @import("../../platform/io.zig");
pub fn configRead(slot: u8, offset: u8) u32 {
    const address: u32 = 0x80000000 | (@as(u32, slot) << 11) | (offset & 0xfc);
    asm volatile ("outl %[a], %[p]"
        :
        : [a] "{eax}" (address),
          [p] "{dx}" (@as(u16, 0xcf8)),
        : .{ .memory = true });
    return asm volatile ("inl %[p], %[a]"
        : [a] "={eax}" (-> u32),
        : [p] "{dx}" (@as(u16, 0xcfc)),
        : .{ .memory = true });
}
pub fn configWrite(slot: u8, offset: u8, value: u32) void {
    const address: u32 = 0x80000000 | (@as(u32, slot) << 11) | (offset & 0xfc);
    asm volatile ("outl %[a], %[p]"
        :
        : [a] "{eax}" (address),
          [p] "{dx}" (@as(u16, 0xcf8)),
        : .{ .memory = true });
    asm volatile ("outl %[a], %[p]"
        :
        : [a] "{eax}" (value),
          [p] "{dx}" (@as(u16, 0xcfc)),
        : .{ .memory = true });
}
pub fn read(comptime T: type, port: u64) T {
    return switch (T) {
        u8 => io.in8(@intCast(port)),
        u16 => asm volatile ("inw %[p], %[v]"
            : [v] "={ax}" (-> u16),
            : [p] "{dx}" (@as(u16, @intCast(port))),
            : .{ .memory = true }),
        u32 => asm volatile ("inl %[p], %[v]"
            : [v] "={eax}" (-> u32),
            : [p] "{dx}" (@as(u16, @intCast(port))),
            : .{ .memory = true }),
        else => @compileError("Invalid port width"),
    };
}
pub fn write(comptime T: type, port: u64, value: T) void {
    switch (T) {
        u8 => io.out8(@intCast(port), value),
        u16 => asm volatile ("outw %[v], %[p]"
            :
            : [v] "{ax}" (value),
              [p] "{dx}" (@as(u16, @intCast(port))),
            : .{ .memory = true }),
        u32 => asm volatile ("outl %[v], %[p]"
            :
            : [v] "{eax}" (value),
              [p] "{dx}" (@as(u16, @intCast(port))),
            : .{ .memory = true }),
        else => @compileError("Invalid port width"),
    }
}
