//! Device accesses are volatile and distinct from ordinary RAM accesses.
const builtin = @import("builtin");
pub fn read(comptime T: type, address: usize) T {
    return @as(*volatile T, @ptrFromInt(address)).*;
}
pub fn write(comptime T: type, address: usize, value: T) void {
    @as(*volatile T, @ptrFromInt(address)).* = value;
}
pub fn in8(port: u16) u8 {
    if (comptime builtin.cpu.arch != .x86_64) @compileError("Port I/O requires x86");
    return asm volatile ("inb %[port], %[value]"
        : [value] "={al}" (-> u8),
        : [port] "{dx}" (port),
        : .{ .memory = true });
}
pub fn out8(port: u16, value: u8) void {
    if (comptime builtin.cpu.arch != .x86_64) @compileError("Port I/O requires x86");
    asm volatile ("outb %[value], %[port]"
        :
        : [port] "{dx}" (port),
          [value] "{al}" (value),
        : .{ .memory = true });
}
