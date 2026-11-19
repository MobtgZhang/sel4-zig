//! Loongson IOCSR mailbox and IPI startup as implemented by QEMU virt firmware.
extern fn secondary_entry() void;
pub fn ticks() u64 {
    return asm volatile ("rdtime.d %[value], $zero"
        : [value] "=r" (-> u64),
    );
}
pub const timeout_ticks: u64 = 200_000_000;
fn write64(address: u32, value: u64) void {
    asm volatile ("iocsrwr.d %[value], %[address]"
        :
        : [value] "r" (value),
          [address] "r" (address),
        : .{ .memory = true });
}
pub fn start(id: u64, _: usize) !void {
    if (id > 1023) return error.UnsupportedCpuId;
    const entry = @intFromPtr(&secondary_entry) & 0x0000ffffffffffff;
    const target = (@as(u64, 1) << 31) | (id << 16);
    // Mailbox zero consists of independently addressed low/high 32-bit halves.
    write64(0x1048, target | (@as(u64, 1) << 2) | (entry & 0xffffffff00000000));
    write64(0x1048, target | (entry << 32));
    asm volatile ("dbar 0; iocsrwr.w %[value], %[address]"
        :
        : [value] "r" (@as(u32, 0x80000000) | @as(u32, @intCast(id << 16))),
          [address] "r" (@as(u32, 0x1040)),
        : .{ .memory = true });
}
