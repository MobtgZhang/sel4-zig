//! Invalidate every local ASID, including global entries, before acknowledgement.
pub fn invalidateAll() void {
    asm volatile ("dbar 0; invtlb 0, $zero, $zero; dbar 0; ibar 0" ::: .{ .memory = true });
}
pub fn readUser(address: usize) u64 {
    return @as(*const volatile u64, @ptrFromInt(address)).*;
}
