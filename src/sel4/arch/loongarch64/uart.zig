//! QEMU virt byte-addressed NS16550 console.
const io = @import("../../platform/io.zig");
const base = @import("../../plat/qemu_loongarch64_virt.zig").uart0_mmio_base;
pub fn init() void {}
pub fn serialPutChar(byte: u8) void {
    while (io.read(u8, base + 5) & 0x20 == 0) {}
    io.write(u8, base, byte);
}
pub fn serialWriteSlice(bytes: []const u8) void {
    for (bytes) |byte| serialPutChar(byte);
}
pub fn serialReadByte() ?u8 {
    if (io.read(u8, base + 5) & 1 == 0) return null;
    return io.read(u8, base);
}
