//! Only SIE is changed; floating-point and address-space status are preserved.
pub fn saveDisable() u64 {
    return asm volatile ("csrrci %[flags], sstatus, 2"
        : [flags] "=r" (-> u64),
        :
        : .{ .memory = true });
}
pub fn restore(flags: u64) void {
    if (flags & 2 != 0) asm volatile ("csrsi sstatus, 2" ::: .{ .memory = true });
}
