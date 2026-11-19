//! Preserve all asynchronous exception masks, including nested critical sections.
pub fn saveDisable() u64 {
    return asm volatile ("mrs %[flags], daif; msr daifset, #0xf"
        : [flags] "=r" (-> u64),
        :
        : .{ .memory = true });
}
pub fn restore(flags: u64) void {
    asm volatile ("msr daif, %[flags]"
        :
        : [flags] "r" (flags),
        : .{ .memory = true });
}
