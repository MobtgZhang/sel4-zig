//! Save and restore the caller's interrupt-enable state around a critical section.
pub fn saveDisable() u64 {
    return asm volatile ("pushfq; popq %[flags]; cli"
        : [flags] "=r" (-> u64),
        :
        : .{ .memory = true });
}
pub fn restore(flags: u64) void {
    if (flags & (1 << 9) != 0) asm volatile ("sti" ::: .{ .memory = true });
}
