//! AArch64 stage-1 4 KiB descriptor primitives (ARMv8-A).
const std = @import("std");
pub const upstream_rel = "arch/arm/64/kernel/vspace.c";
pub const valid: u64 = 1;
pub const table_or_page: u64 = 2;
pub const access_flag: u64 = 1 << 10;
pub const user_execute_never: u64 = 1 << 54;
pub const privileged_execute_never: u64 = 1 << 53;
pub const address_mask: u64 = 0x0000fffffffff000;
pub fn isPresent(entry: u64) bool {
    return entry & valid != 0;
}
pub fn pageDescriptor(physical: u64, user: bool, writable: bool, executable: bool) error{InvalidAddress}!u64 {
    if (physical & ~address_mask != 0) return error.InvalidAddress;
    const ap: u64 = (if (user) @as(u64, 1) else 0) | (if (writable) @as(u64, 0) else 2);
    return physical | valid | table_or_page | access_flag | (3 << 8) | (ap << 6) | privileged_execute_never | (if (executable) @as(u64, 0) else user_execute_never);
}
test "AArch64 descriptors enforce read-only and execute-never permissions" {
    const entry = try pageDescriptor(0x2000, true, false, false);
    try std.testing.expect(isPresent(entry) and entry & user_execute_never != 0);
    try std.testing.expectEqual(@as(u64, 3), (entry >> 6) & 3);
    try std.testing.expectError(error.InvalidAddress, pageDescriptor(0x2001, true, true, true));
}
