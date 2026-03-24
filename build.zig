//! seL4-Zig 构建：UEFI、多架构裸 ELF 内核、迁移测试。
const std = @import("std");
const kernel_types = @import("src/sel4/config/options_types.zig");

const KernelConfig = struct {
    max_num_nodes: u32 = 1,
    num_domains: u32 = 1,
    kernel_debug_build: bool = false,
    kernel_max_num_bootinfo_untyped_caps: u32 = 230,
};

fn addKernelBuildOptions(
    b: *std.Build,
    kcfg: KernelConfig,
    arch: kernel_types.KernelArch,
    platform: kernel_types.KernelPlatform,
) *std.Build.Step.Options {
    const o = b.addOptions();
    o.addOption(kernel_types.KernelArch, "kernel_arch", arch);
    o.addOption(kernel_types.KernelPlatform, "kernel_platform", platform);
    o.addOption(u32, "max_num_nodes", kcfg.max_num_nodes);
    o.addOption(u32, "num_domains", kcfg.num_domains);
    o.addOption(bool, "kernel_debug_build", kcfg.kernel_debug_build);
    o.addOption(u32, "kernel_max_num_bootinfo_untyped_caps", kcfg.kernel_max_num_bootinfo_untyped_caps);
    return o;
}

fn kernelCpuArch(arch: kernel_types.KernelArch) std.Target.Cpu.Arch {
    return switch (arch) {
        .x86_64 => .x86_64,
        .aarch64 => .aarch64,
        .riscv64 => .riscv64,
        .loongarch64 => .loongarch64,
    };
}

fn kernelImageBase(arch: kernel_types.KernelArch) u64 {
    return switch (arch) {
        .x86_64 => 0x100000,
        .aarch64 => 0x40000000,
        .riscv64 => 0x80200000,
        .loongarch64 => 0x9000000010000000,
    };
}

fn kernelLinkerScript(arch: kernel_types.KernelArch) []const u8 {
    return switch (arch) {
        .x86_64 => "linker/kernel_x86_64.ld",
        .aarch64 => "linker/kernel_aarch64.ld",
        .riscv64 => "linker/kernel_riscv64.ld",
        .loongarch64 => "linker/kernel_loongarch64.ld",
    };
}

fn addBareKernelElf(
    b: *std.Build,
    optimize: std.builtin.OptimizeMode,
    kcfg: KernelConfig,
    arch: kernel_types.KernelArch,
    platform: kernel_types.KernelPlatform,
    exe_name: []const u8,
) void {
    const ko = addKernelBuildOptions(b, kcfg, arch, platform);
    const target = b.resolveTargetQuery(.{
        .cpu_arch = kernelCpuArch(arch),
        .os_tag = .freestanding,
        .abi = .none,
    });
    const mod = b.createModule(.{
        .root_source_file = b.path("src/sel4/kmain.zig"),
        .target = target,
        .optimize = optimize,
        .code_model = switch (arch) {
            .riscv64, .loongarch64 => .medium,
            else => .default,
        },
    });
    mod.addOptions("kernel_build_options", ko);
    mod.unwind_tables = .none;
    mod.strip = true;

    switch (arch) {
        .x86_64 => {
            mod.addAssemblyFile(b.path("src/sel4/baremetal/multiboot2_longmode.S"));
            mod.addAssemblyFile(b.path("src/sel4/baremetal/isr_de.S"));
            mod.addAssemblyFile(b.path("src/sel4/baremetal/isr_pf.S"));
            mod.addAssemblyFile(b.path("src/sel4/baremetal/idt_asm.S"));
        },
        .aarch64 => mod.addAssemblyFile(b.path("src/sel4/arch/aarch64/entry.S")),
        .riscv64 => mod.addAssemblyFile(b.path("src/sel4/arch/riscv64/entry.S")),
        .loongarch64 => mod.addAssemblyFile(b.path("src/sel4/arch/loongarch64/entry.S")),
    }

    const exe = b.addExecutable(.{
        .name = exe_name,
        .root_module = mod,
    });
    exe.entry = .{ .symbol_name = "_start" };
    exe.image_base = kernelImageBase(arch);
    exe.setLinkerScript(b.path(kernelLinkerScript(arch)));
    b.installArtifact(exe);
}

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const uefi_target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .uefi,
        .abi = .none,
    });

    const uefi_mod = b.createModule(.{
        .root_source_file = b.path("src/uefi_main.zig"),
        .target = uefi_target,
        .optimize = optimize,
    });

    const bootx64 = b.addExecutable(.{
        .name = "BOOTX64",
        .root_module = uefi_mod,
    });
    b.installArtifact(bootx64);

    const qemu = b.step(
        "qemu",
        "scripts/run-qemu-uefi.sh：QEMU + OVMF 运行 BOOTX64.efi",
    );
    const run = b.addSystemCommand(&.{"bash"});
    run.addFileArg(b.path("scripts/run-qemu-uefi.sh"));
    run.stdio = .inherit;
    run.has_side_effects = true;
    run.step.dependOn(b.getInstallStep());
    qemu.dependOn(&run.step);

    const verify_nographic = b.addSystemCommand(&.{"bash"});
    verify_nographic.addFileArg(b.path("scripts/run-qemu-uefi-nographic.sh"));
    verify_nographic.stdio = .inherit;
    verify_nographic.has_side_effects = true;
    verify_nographic.step.dependOn(b.getInstallStep());
    const verify_step = b.step(
        "verify-uefi",
        "阶段六 6.1：QEMU+OVMF+fat ESP，-nographic + serial stdio",
    );
    verify_step.dependOn(&verify_nographic.step);

    const kcfg = KernelConfig{};
    const kernel_opts_default = addKernelBuildOptions(b, kcfg, .x86_64, .pc99);
    uefi_mod.addOptions("kernel_build_options", kernel_opts_default);

    const syscall_nums_mod = b.createModule(.{
        .root_source_file = b.path("src/sel4/api/syscall_numbers.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });

    const bare_optimize: std.builtin.OptimizeMode = .ReleaseSmall;

    addBareKernelElf(b, bare_optimize, kcfg, .x86_64, .pc99, "kernel.elf");
    addBareKernelElf(b, bare_optimize, kcfg, .aarch64, .qemu_aarch64_virt, "kernel-aarch64.elf");
    addBareKernelElf(b, bare_optimize, kcfg, .riscv64, .qemu_riscv64_virt, "kernel-riscv64.elf");
    addBareKernelElf(b, bare_optimize, kcfg, .loongarch64, .qemu_loongarch64_virt, "kernel-loongarch64.elf");

    const kernel_qemu = b.addSystemCommand(&.{"bash"});
    kernel_qemu.addFileArg(b.path("scripts/run-bare-kernel-qemu.sh"));
    kernel_qemu.step.dependOn(b.getInstallStep());
    kernel_qemu.stdio = .inherit;
    kernel_qemu.has_side_effects = true;
    const kernel_qemu_step = b.step(
        "kernel-qemu",
        "GRUB multiboot2 + QEMU：串口输出裸机 kernel.elf（x86_64）",
    );
    kernel_qemu_step.dependOn(&kernel_qemu.step);

    const kernel_qemu_direct = b.addSystemCommand(&.{"qemu-system-x86_64"});
    kernel_qemu_direct.addArgs(&.{
        "-machine", "q35",
        "-m",       "128M",
        "-kernel",  "zig-out/bin/kernel.elf",
        "-serial",  "stdio",
        "-display", "none",
        "-no-reboot",
        "-no-shutdown",
    });
    kernel_qemu_direct.step.dependOn(b.getInstallStep());
    kernel_qemu_direct.stdio = .inherit;
    kernel_qemu_direct.has_side_effects = true;
    const kernel_qemu_direct_step = b.step(
        "kernel-qemu-direct",
        "qemu -kernel kernel.elf（PVH note，x86_64）",
    );
    kernel_qemu_direct_step.dependOn(&kernel_qemu_direct.step);

    const kqa = b.addSystemCommand(&.{"bash"});
    kqa.addFileArg(b.path("scripts/run-bare-kernel-qemu-aarch64.sh"));
    kqa.step.dependOn(b.getInstallStep());
    kqa.stdio = .inherit;
    kqa.has_side_effects = true;
    b.step("kernel-qemu-aarch64", "qemu-system-aarch64 -kernel kernel-aarch64.elf").dependOn(&kqa.step);

    const kqr = b.addSystemCommand(&.{"bash"});
    kqr.addFileArg(b.path("scripts/run-bare-kernel-qemu-riscv64.sh"));
    kqr.step.dependOn(b.getInstallStep());
    kqr.stdio = .inherit;
    kqr.has_side_effects = true;
    b.step("kernel-qemu-riscv64", "qemu-system-riscv64 -kernel kernel-riscv64.elf").dependOn(&kqr.step);

    const kql = b.addSystemCommand(&.{"bash"});
    kql.addFileArg(b.path("scripts/run-bare-kernel-qemu-loongarch64.sh"));
    kql.step.dependOn(b.getInstallStep());
    kql.stdio = .inherit;
    kql.has_side_effects = true;
    b.step("kernel-qemu-loongarch64", "qemu-system-loongarch64 -kernel kernel-loongarch64.elf").dependOn(&kql.step);

    const bare_target_x86 = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
    });
    const uefi_kernel_mod = b.createModule(.{
        .root_source_file = b.path("src/sel4/kmain.zig"),
        .target = bare_target_x86,
        .optimize = bare_optimize,
    });
    uefi_kernel_mod.addOptions("kernel_build_options", kernel_opts_default);
    uefi_kernel_mod.unwind_tables = .none;
    uefi_kernel_mod.strip = true;
    uefi_kernel_mod.addAssemblyFile(b.path("src/sel4/baremetal/isr_de.S"));
    uefi_kernel_mod.addAssemblyFile(b.path("src/sel4/baremetal/isr_pf.S"));
    uefi_kernel_mod.addAssemblyFile(b.path("src/sel4/baremetal/idt_asm.S"));

    const kernel_uefi_elf = b.addExecutable(.{
        .name = "kernel-uefi.elf",
        .root_module = uefi_kernel_mod,
    });
    kernel_uefi_elf.pie = true;
    kernel_uefi_elf.entry = .{ .symbol_name = "kmain" };
    kernel_uefi_elf.image_base = 0x1000000;
    kernel_uefi_elf.setLinkerScript(b.path("linker/kernel_uefi_x86_64.ld"));
    b.installArtifact(kernel_uefi_elf);

    const libsel4_mod = b.createModule(.{
        .root_source_file = b.path("libsel4/src/sel4.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    libsel4_mod.addImport("syscall_nums", syscall_nums_mod);

    const migration_mod = b.createModule(.{
        .root_source_file = b.path("src/sel4/migration_tests.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    migration_mod.addImport("libsel4", libsel4_mod);
    migration_mod.addImport("syscall_nums", syscall_nums_mod);
    migration_mod.addOptions("kernel_build_options", kernel_opts_default);
    switch (b.graph.host.result.cpu.arch) {
        .x86_64 => migration_mod.addAssemblyFile(b.path("src/sel4/fastpath/placeholder_x86_64.s")),
        .aarch64 => migration_mod.addAssemblyFile(b.path("src/sel4/fastpath/placeholder_aarch64.s")),
        .riscv64 => migration_mod.addAssemblyFile(b.path("src/sel4/fastpath/placeholder_riscv64.s")),
        else => {},
    }

    const migration_tests = b.addTest(.{
        .root_module = migration_mod,
    });

    const run_migration_tests = b.addRunArtifact(migration_tests);
    const test_step = b.step("test", "阶段三～六：单元测试（对照 idea1.md 6.2 / sel4test 替代策略）");
    test_step.dependOn(&run_migration_tests.step);

    const sel4_codegen = b.addSystemCommand(&.{ "bash" });
    sel4_codegen.addFileArg(b.path("tools/sel4_copy_generated.sh"));
    sel4_codegen.has_side_effects = true;
    const sel4_codegen_step = b.step(
        "sel4-codegen",
        "设置 SEL4_BUILD 时复制官方 CMake 生成头到 zig-cache/sel4-gen（见 docs/kernel_config_cmake_crosswalk.md）",
    );
    sel4_codegen_step.dependOn(&sel4_codegen.step);

    const verify_kernel_handoff = b.addSystemCommand(&.{ "bash" });
    verify_kernel_handoff.addFileArg(b.path("scripts/verify-kernel-uefi-handoff.sh"));
    verify_kernel_handoff.step.dependOn(b.getInstallStep());
    verify_kernel_handoff.has_side_effects = true;
    const verify_kh_step = b.step(
        "verify-kernel-handoff",
        "QEMU+OVMF：ESP 上 kernel-uefi.elf，串口断言 kernelInit",
    );
    verify_kh_step.dependOn(&verify_kernel_handoff.step);
}
