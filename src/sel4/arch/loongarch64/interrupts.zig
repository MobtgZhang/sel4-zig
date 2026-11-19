//! Exchange only CRMD.IE, preserving paging mode, privilege and cache attributes.
pub fn saveDisable() u64 {
    return asm volatile ("csrxchg %[value], %[mask], 0"
        : [value] "=r" (-> u64),
        : [initial] "0" (@as(u64, 0)),
          [mask] "r" (@as(u64, 4)),
        : .{ .memory = true });
}
pub fn restore(flags: u64) void {
    _ = asm volatile ("csrxchg %[value], %[mask], 0"
        : [value] "=r" (-> u64),
        : [initial] "0" (flags),
          [mask] "r" (@as(u64, 4)),
        : .{ .memory = true });
}
