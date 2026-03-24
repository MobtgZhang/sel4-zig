//! 阶段二：UEFI 应用；阶段四：`PhysRegion`；阶段 B：`ExitBootServices` + 载入 `kernel-uefi.elf`。
const std = @import("std");
const uefi = std.os.uefi;
const con = @import("console.zig");
const phys_region = @import("../sel4/mm/phys_region.zig");
const kernel_elf_load = @import("kernel_elf_load.zig");

pub fn run() void {
    const st = uefi.system_table;
    const out = st.con_out orelse return;
    const bs = st.boot_services orelse return;

    _ = out.reset(false) catch {};

    con.puts(out, "seL4-Zig: UEFI x86_64 stage 2\r\n");
    con.puts(out, "----------------------------------------\r\n");

    const kb = @import("kernel_build_options");
    con.puts(out, "Phase5 KernelConfig (build.zig addOptions):\r\n");
    con.puts(out, "  arch: ");
    switch (kb.kernel_arch) {
        .x86_64 => con.puts(out, "x86_64\r\n"),
        .aarch64 => con.puts(out, "aarch64\r\n"),
        .riscv64 => con.puts(out, "riscv64\r\n"),
        .loongarch64 => con.puts(out, "loongarch64\r\n"),
    }
    con.puts(out, "  platform: ");
    switch (kb.kernel_platform) {
        .pc99 => con.puts(out, "pc99\r\n"),
        .qemu_aarch64_virt => con.puts(out, "qemu_aarch64_virt\r\n"),
        .qemu_riscv64_virt => con.puts(out, "qemu_riscv64_virt\r\n"),
        .qemu_loongarch64_virt => con.puts(out, "qemu_loongarch64_virt\r\n"),
    }
    con.puts(out, "  max_num_nodes: ");
    con.printU64(out, kb.max_num_nodes);
    con.puts(out, "\r\n  num_domains: ");
    con.printU64(out, kb.num_domains);
    con.puts(out, "\r\n  kernel_debug_build: ");
    con.puts(out, if (kb.kernel_debug_build) "true\r\n" else "false\r\n");
    con.puts(out, "  bootinfo_untyped_caps: ");
    con.printU64(out, kb.kernel_max_num_bootinfo_untyped_caps);
    con.puts(out, "\r\n----------------------------------------\r\n");

    const map_info = bs.getMemoryMapInfo() catch {
        con.puts(out, "[!] getMemoryMapInfo failed\r\n");
        return;
    };

    con.puts(out, "Memory map descriptors: ");
    con.printU64(out, @intCast(map_info.len));
    con.puts(out, "\r\nDescriptor size: ");
    con.printU64(out, @intCast(map_info.descriptor_size));
    con.puts(out, "\r\n");

    var mmap_buf: [32768]u8 align(@alignOf(uefi.tables.MemoryDescriptor)) = undefined;
    const map_slice = bs.getMemoryMap(@as([]align(@alignOf(uefi.tables.MemoryDescriptor)) u8, &mmap_buf)) catch {
        con.puts(out, "[!] getMemoryMap failed\r\n");
        return;
    };

    var conv_pages: u64 = 0;
    var it = map_slice.iterator();
    while (it.next()) |desc| {
        if (desc.type == .conventional_memory)
            conv_pages += desc.number_of_pages;
    }
    con.puts(out, "Conventional RAM (4KiB pages): ");
    con.printU64(out, conv_pages);
    con.puts(out, "\r\n");

    var pregions: [64]phys_region.PhysRegion = undefined;
    const nreg = phys_region.fromUefiMemoryMapSlice(&pregions, map_slice);
    con.puts(out, "Phase4 PhysRegion slots used (cap=64): ");
    con.printU64(out, @intCast(nreg));
    con.puts(out, "\r\n");

    if (bs.locateProtocol(uefi.protocol.GraphicsOutput, null) catch null) |gop| {
        const info = gop.mode.info;
        con.puts(out, "GOP: ");
        con.printU64(out, @intCast(info.horizontal_resolution));
        con.puts(out, "x");
        con.printU64(out, @intCast(info.vertical_resolution));
        con.puts(out, "\r\n");
    } else {
        con.puts(out, "GOP: not available\r\n");
    }

    con.puts(out, "----------------------------------------\r\n");
    con.puts(out, "Phase B: scan FAT for KERNEL.ELF / kernel-uefi.elf → ExitBootServices → kmain(handoff)\r\n");

    kernel_elf_load.loadHandoffAndJumpToKernel(bs, pregions[0..nreg]) catch |err| {
        con.puts(out, "[!] kernel handoff skipped: ");
        switch (err) {
            error.NoKernelElf => con.puts(out, "NoKernelElf"),
            error.NoSimpleFs => con.puts(out, "NoSimpleFs"),
            error.BadKernelSize => con.puts(out, "BadKernelSize"),
            error.ReadFailed => con.puts(out, "ReadFailed"),
            error.BadElf => con.puts(out, "BadElf"),
            error.Not64 => con.puts(out, "Not64"),
            error.NotExec => con.puts(out, "NotExec"),
            error.NotX86_64 => con.puts(out, "NotX86_64"),
            error.NoPhdr => con.puts(out, "NoPhdr"),
            error.BadPhdr => con.puts(out, "BadPhdr"),
            error.HandoffAllocFailed => con.puts(out, "HandoffAllocFailed"),
            error.ExitBootServicesFailed => con.puts(out, "ExitBootServicesFailed"),
            error.OutOfResources => con.puts(out, "OutOfResources"),
            error.InvalidParameter => con.puts(out, "InvalidParameter"),
            error.NotFound => con.puts(out, "NotFound"),
            else => con.puts(out, "unknown"),
        }
        con.puts(out, " (place kernel-uefi.elf on ESP root or EFI\\\\BOOT\\\\)\r\n");
        con.puts(out, "Idling in Boot Services. QEMU: Ctrl+A then X.\r\n");
        while (true) {
            _ = bs.stall(std.time.us_per_s) catch {};
        }
    };
}
