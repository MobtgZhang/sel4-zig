//! QEMU virt PL011 early console.
const io = @import("../../platform/io.zig");
const base = @import("../../plat/qemu_aarch64_virt.zig").uart0_mmio_base;
pub fn init() void {
    io.write(u32, base + 0x30, 0);
    io.write(u32, base + 0x24, 13);
    io.write(u32, base + 0x28, 1);
    io.write(u32, base + 0x2c, 0x70);
    io.write(u32, base + 0x30, 0x301);
}
pub fn serialPutChar(byte: u8) void {
    while (io.read(u32, base + 0x18) & (1 << 5) != 0) {}
    io.write(u32, base, byte);
}
pub fn serialWriteSlice(bytes: []const u8) void {
    for (bytes) |byte| serialPutChar(byte);
}
pub fn serialReadByte() ?u8 {
    if (io.read(u32, base + 0x18) & (1 << 4) != 0) return null;
    const value = io.read(u32, base);
    if (value & 0xf00 != 0) {
        io.write(u32, base + 4, 0);
        return null;
    }
    return @truncate(value);
}
