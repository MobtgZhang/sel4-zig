//! Publish page-table writes, invalidate locally, and complete the table walk barrier.
pub fn invalidateAll() void {
    asm volatile ("dsb ishst; tlbi vmalle1; dsb ish; isb" ::: .{ .memory = true });
}
pub fn readUser(address: usize) u64 {
    return @as(*const volatile u64, @ptrFromInt(address)).*;
}
