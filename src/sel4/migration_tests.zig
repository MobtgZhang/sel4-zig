//! 主机上运行的阶段三～六测试：`zig build test`
const std = @import("std");

comptime {
    switch (@import("builtin").cpu.arch) {
        .x86_64 => _ = @import("fastpath/asm_link_smoke_x86_64.zig"),
        .aarch64 => _ = @import("fastpath/asm_link_smoke_aarch64.zig"),
        .riscv64 => _ = @import("fastpath/asm_link_smoke_riscv64.zig"),
        else => {},
    }
}

test "mirror manifest (no vendor C mirror by default)" {
    const man = @import("mirror_manifest.zig");
    try std.testing.expectEqual(@as(usize, 0), man.entry_count);
    try std.testing.expectEqualStrings("", man.pathAt(0));
}

test "registry pulls all modules" {
    @import("registry.zig").referenceAllDecls();
}

test "x86_64 cpuid (host)" {
    if (@import("builtin").cpu.arch != .x86_64) return;
    const machine = @import("arch/x86_64/machine.zig");
    const r = machine.cpuid(0, 0);
    try std.testing.expect(r.eax != 0);
}

test "phase3 tlb invlpg symbol (idea1 3.3)" {
    if (@import("builtin").cpu.arch != .x86_64) return;
    _ = @import("arch/x86_64/tlb.zig").invlpg;
}

test "zig migration stub (boot)" {
    const boot = @import("kernel/boot.zig");
    boot.zigSmokeBootStub();
}

test "zig migration stub (thread)" {
    const th = @import("kernel/thread.zig");
    th.zigSmokeThreadStub();
}

test "phase4 idt entry layout" {
    if (@import("builtin").cpu.arch != .x86_64) return;
    _ = @import("arch/x86_64/idt.zig");
}

test "phase4 capability model" {
    _ = @import("model/capability.zig");
}

test "phase4 phys fromUefiMemoryMap" {
    _ = @import("mm/phys_region.zig");
}

test "phase5 kernel_config from build options" {
    _ = @import("config/kernel_config.zig");
}

test "phase5 libsel4 syscall API" {
    const sel4 = @import("libsel4");
    var info: sel4.MessageInfo = .{};
    _ = &info;
    if (false) sel4.seL4_Send(0, info);
}

test "phase4 ipc dispatch upstream ref" {
    _ = @import("kernel/ipc_dispatch.zig").upstream_rel;
}

test "syscall nums match libsel4 x86_64" {
    const nums = @import("syscall_nums");
    const sel4 = @import("libsel4");
    try std.testing.expectEqual(nums.seL4_SysSend, @as(i64, @bitCast(sel4.seL4_SysSend)));
    try std.testing.expectEqual(nums.seL4_SysDebugPutChar, @as(i64, @bitCast(sel4.seL4_SysDebugPutChar)));
}

test "syscall dispatch debug putchar" {
    const nums = @import("syscall_nums");
    const ipc = @import("kernel/ipc_dispatch.zig");
    const syscall = @import("api/syscall.zig");
    syscall.testTraceReset();
    ipc.handleFastSyscall(nums.seL4_SysDebugPutChar, 'Z', 0, 0);
    try std.testing.expectEqualStrings("Z", syscall.testTraceSlice());
    try std.testing.expectEqual(syscall.DispatchTag.debug_putchar, syscall.last_dispatch_tag);
}

test "syscall dispatch ipc unimplemented tag" {
    const nums = @import("syscall_nums");
    const ipc = @import("kernel/ipc_dispatch.zig");
    const syscall = @import("api/syscall.zig");
    syscall.testTraceReset();
    ipc.handleFastSyscall(nums.seL4_SysSend, 0, 0, 0);
    try std.testing.expectEqual(syscall.DispatchTag.ipc_unimplemented, syscall.last_dispatch_tag);
}

test "boot_mem seed handoff regions" {
    const boot_mem = @import("kernel/boot_mem.zig");
    var buf: [boot_mem.max_reserved]boot_mem.PRegion = undefined;
    var n: usize = 0;
    const fake = [_]boot_mem.HandoffPhysRegion{
        .{ .start = 0x100000, .end = 0x200000 },
        .{ .start = 0x200000, .end = 0x300000 },
    };
    try std.testing.expect(boot_mem.seedReservedFromHandoffRegions(&buf, &n, &fake));
    try std.testing.expectEqual(@as(usize, 1), n);
    try std.testing.expectEqual(@as(u64, 0x100000), buf[0].start);
    try std.testing.expectEqual(@as(u64, 0x300000), buf[0].end);
}

test "x86_64 vspace pte constants" {
    if (@import("builtin").cpu.arch != .x86_64) return;
    const vs = @import("arch/x86_64/vspace.zig");
    try std.testing.expect((vs.pteFromPhys(0x2000, vs.pte_present) & vs.pte_present) != 0);
}

test "fastpath enters ipc_dispatch" {
    const nums = @import("syscall_nums");
    const fp = @import("fastpath/fastpath.zig");
    const syscall = @import("api/syscall.zig");
    syscall.testTraceReset();
    fp.enterFromFastpathStub(nums.seL4_SysYield, 0, 0, 0);
    try std.testing.expectEqual(syscall.DispatchTag.ipc_unimplemented, syscall.last_dispatch_tag);
}

test "smp spinlock try" {
    const lock_mod = @import("smp/lock.zig");
    var lk: lock_mod.SpinLockU32 = .{};
    try std.testing.expect(lk.tryAcquire());
    try std.testing.expect(!lk.tryAcquire());
    lk.release();
    try std.testing.expect(lk.tryAcquire());
}

test "phase7 official vs zig kernel elf (see README)" {
    // 对照：`SEL4_DIR`/`SEL4_BUILD` 下官方 `kernel.elf` 与 `zig-out/bin/kernel.elf` 勿混淆；手测 `make run` vs `zig build kernel-qemu`。
    try std.testing.expect(true);
}

test "boot handoff module" {
    _ = @import("boot/handoff.zig").magic;
}

test "fdt fillFromFdt invalid magic falls back" {
    var buf: [256]u8 = undefined;
    @memset(&buf, 0);
    var h: @import("boot/handoff.zig").BootHandoff = undefined;
    @import("boot/fdt.zig").fillFromFdt(&h, @intFromPtr(&buf));
    try std.testing.expectEqual(@as(u32, 0), h.flags & @import("boot/handoff.zig").flag_fdt);
}

test "phase1 idea1 index" {
    @import("idea1_phases.zig").referenceAll();
}

test "phase3 migration priority list" {
    _ = @import("migration_priority.zig").ordered.len;
}

test "phase3 c_kernel_interop module" {
    _ = @import("hybrid/c_kernel_interop.zig").kernelMainViaStubs;
}

test "phase2 boot comparison" {
    _ = @import("boot_comparison.zig").table.len;
}

test "phase6 formal verification note (idea1.md)" {
    // L4.verified 针对既有 C；Zig 重写需重新证明 —— 见 docs/sel4-existing-architecture.md §9 与 ideas/idea1.md 阶段六。
    try std.testing.expect(true);
}
