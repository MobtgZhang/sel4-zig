//! Firmware image cache maintenance and architecture calling convention.
pub const elf_machine = @import("std").elf.EM.RISCV;
/// Firmware owns tp; only the RISC-V boot protocol identifies the boot hart.
pub fn bootHartId(bs: *@import("std").os.uefi.tables.BootServices) !u64 {
    const uefi = @import("std").os.uefi;
    const Protocol = extern struct {
        revision: u64,
        get_boot_hart_id: *const fn (*const @This(), *usize) callconv(uefi.cc) uefi.Status,
        pub const guid: uefi.Guid = .{
            .time_low = 0xccd15fec,
            .time_mid = 0x6f73,
            .time_high_and_version = 0x4eec,
            .clock_seq_high_and_reserved = 0x83,
            .clock_seq_low = 0x95,
            .node = .{ 0x3e, 0x69, 0xe4, 0xb9, 0x40, 0xbf },
        };
    };
    const protocol = (try bs.locateProtocol(Protocol, null)) orelse return error.NoBootHartProtocol;
    var id: usize = undefined;
    try protocol.get_boot_hart_id(protocol, &id).err();
    return id;
}
pub fn physical(address: u64) u64 {
    return address;
}
pub fn prepare(_: u64, _: usize) void {
    asm volatile ("fence rw, rw; fence.i" ::: .{ .memory = true });
}
pub fn jump(entry: u64, handoff: u64) noreturn {
    asm volatile ("csrci sstatus, 2" ::: .{ .memory = true });
    const h: *const @import("../../boot/handoff.zig").BootHandoff = @ptrFromInt(handoff);
    const start: *const fn (u64, u64) callconv(.c) noreturn = @ptrFromInt(entry);
    start(handoff, h.boot_cpu_id);
}
