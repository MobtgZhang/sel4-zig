//! QEMU virt PCI ECAM and legacy I/O aperture in the uncached direct window.
const io = @import("../../platform/io.zig");
pub fn configRead(slot: u8, offset: u8) u32 {
    return io.read(u32, 0x8000000020000000 + (@as(usize, slot) << 15) + offset);
}
pub fn configWrite(slot: u8, offset: u8, value: u32) void {
    io.write(u32, 0x8000000020000000 + (@as(usize, slot) << 15) + offset, value);
}
pub fn read(comptime T: type, port: u64) T {
    return io.read(T, @intCast(0x8000000018000000 + port));
}
pub fn write(comptime T: type, port: u64, value: T) void {
    io.write(T, @intCast(0x8000000018000000 + port), value);
}
