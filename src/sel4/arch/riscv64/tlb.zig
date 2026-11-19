//! SFENCE.VMA is local; the common protocol waits for every remote hart.
pub fn invalidateAll() void {
    asm volatile ("fence rw, rw; sfence.vma; fence.i" ::: .{ .memory = true });
}
pub fn readUser(address: usize) u64 {
    const previous = asm volatile ("csrrs %[v], sstatus, %[mask]"
        : [v] "=r" (-> u64),
        : [mask] "r" (@as(u64, 1 << 18)),
        : .{ .memory = true });
    const value = @as(*const volatile u64, @ptrFromInt(address)).*;
    if (previous & (1 << 18) == 0) asm volatile ("csrc sstatus, %[mask]"
        :
        : [mask] "r" (@as(u64, 1 << 18)),
        : .{ .memory = true });
    return value;
}
