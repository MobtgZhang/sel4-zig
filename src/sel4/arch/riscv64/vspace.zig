//! RISC-V Sv39/Sv48 page-table descriptor primitives.
const std = @import("std");
pub const upstream_rel = "arch/riscv/kernel/vspace.c";
pub const valid: u64 = 1;
pub const read: u64 = 2;
pub const write: u64 = 4;
pub const execute: u64 = 8;
pub const user: u64 = 16;
pub fn isPresent(entry: u64) bool {
    return entry & valid != 0;
}
pub fn isLeaf(entry: u64) bool {
    return entry & (read | write | execute) != 0;
}
pub fn pageDescriptor(physical: u64, flags: u64) error{ InvalidAddress, InvalidRights }!u64 {
    if (physical & 0xfff != 0 or physical >> 56 != 0) return error.InvalidAddress;
    if (flags & (read | execute) == 0 or (flags & write != 0 and flags & read == 0)) return error.InvalidRights;
    // Set accessed/dirty eagerly; hardware-managed A/D updates are not required.
    return ((physical >> 12) << 10) | (flags & 0x3e) | valid | (1 << 6) | (if (flags & write != 0) @as(u64, 1 << 7) else 0);
}
test "RISC-V rejects write-only PTEs and encodes PPN" {
    const entry = try pageDescriptor(0x12345000, read | write | user);
    try std.testing.expect(isPresent(entry) and isLeaf(entry));
    try std.testing.expectEqual(@as(u64, 0x12345000), (entry >> 10) << 12);
    try std.testing.expectError(error.InvalidRights, pageDescriptor(0x1000, write));
}
