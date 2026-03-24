//! 阶段三：集中引用 Zig 迁移模块。`upstream_rel` / `upstream_tree` 相对 **外置** 官方树的 `src/`（默认并列 `../seL4/src`），非本仓路径。可选 `FULL_VENDOR_MIRROR=1` 同步到 `vendor/`。
pub fn referenceAllDecls() void {
    _ = @import("mirror_manifest.zig").entry_count;

    _ = @import("arch/x86_64/machine.zig");
    _ = @import("arch/x86_64/tlb.zig");
    _ = @import("arch/x86_64/mmu.zig");
    _ = @import("arch/x86_64/vspace.zig").pte_present;
    _ = @import("arch/x86_64/registerset.zig").upstream_rel;
    _ = @import("arch/x86_64/fpu.zig").fpuInitStub;
    _ = @import("arch/x86_64/idt.zig");
    _ = @import("arch/x86_bundle.zig").upstream_tree;
    _ = @import("arch/aarch64_bundle.zig").upstream_tree;
    _ = @import("arch/aarch64_bundle.zig").upstream_el64;
    _ = @import("arch/riscv_bundle.zig").upstream_tree;
    _ = @import("arch/loongarch64_bundle.zig").upstream_tree;

    _ = @import("arch/aarch64/machine.zig").zigSmokeMachineStub;
    _ = @import("arch/aarch64/vspace.zig").ptePresentStub;
    _ = @import("arch/riscv64/machine.zig").zigSmokeMachineStub;
    _ = @import("arch/riscv64/vspace.zig").ptePresentStub;
    _ = @import("arch/loongarch64/machine.zig").zigSmokeMachineStub;

    _ = @import("boot/fdt.zig").fillFromFdt;

    _ = @import("kernel/boot.zig").upstream_rel;
    _ = @import("kernel/boot_mem.zig").max_reserved;
    _ = @import("kernel/thread.zig").upstream_rel;
    _ = @import("kernel/cspace.zig").upstream_rel;
    _ = @import("kernel/faulthandler.zig").upstream_rel;
    _ = @import("kernel/sporadic.zig").upstream_rel;
    _ = @import("kernel/stack.zig").upstream_rel;
    _ = @import("kernel/ipc_dispatch.zig").upstream_rel;

    _ = @import("object/cnode.zig").upstream_rel;
    _ = @import("object/endpoint.zig").upstream_rel;
    _ = @import("object/interrupt.zig").upstream_rel;
    _ = @import("object/notification.zig").upstream_rel;
    _ = @import("object/objecttype.zig").upstream_rel;
    _ = @import("object/reply.zig").upstream_rel;
    _ = @import("object/schedcontext.zig").upstream_rel;
    _ = @import("object/schedcontrol.zig").upstream_rel;
    _ = @import("object/tcb.zig").upstream_rel;
    _ = @import("object/untyped.zig").upstream_rel;

    _ = @import("api/faults.zig").upstream_rel;
    _ = @import("api/syscall.zig").upstream_rel;
    _ = @import("api/ipc.zig").upstream_rel;

    _ = @import("fastpath/fastpath.zig").upstream_rel;

    _ = @import("model/statedata.zig").upstream_rel;
    _ = @import("model/smp.zig").upstream_rel;
    _ = @import("model/preemption.zig").upstream_rel;
    _ = @import("model/capability.zig").Capability;

    _ = @import("smp/lock.zig").upstream_rel;
    _ = @import("smp/ipi.zig").upstream_rel;

    _ = @import("root_src/util.zig").upstream_rel;
    _ = @import("root_src/string.zig").upstream_rel;
    _ = @import("root_src/inlines.zig").upstream_rel;

    _ = @import("benchmark/benchmark.zig").upstream_rel;
    _ = @import("idle/idle.zig").upstream_rel;
    _ = @import("idle/idle.zig").upstream_asm_rel;

    _ = @import("drivers/mod.zig").upstream_tree;
    _ = @import("plat/mod.zig").upstream_tree;
    _ = @import("plat/pc99.zig").ioapic_mmio_base;
    _ = @import("plat/qemu_aarch64_virt.zig").uart0_mmio_base;
    _ = @import("plat/qemu_riscv64_virt.zig").uart0_mmio_base;

    _ = @import("config/default_domain.zig").upstream_rel;
    _ = @import("config/kernel_config.zig").arch;

    _ = @import("hybrid/boot_bridge.zig");
    _ = @import("hybrid/c_kernel_interop.zig").kernelMainViaStubs;
    _ = @import("hybrid/migration_stubs.zig").phase3BootStub;

    _ = @import("mm/phys_region.zig").PhysRegion;

    _ = @import("libsel4").seL4_SysSend;

    @import("idea1_phases.zig").referenceAll();
    _ = @import("migration_priority.zig").ordered.len;
    _ = @import("boot_comparison.zig").table.len;
}
