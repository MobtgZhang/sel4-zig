//! 阶段三优先级 2：页表/MMIO 等在上游 `seL4/src/arch/x86/kernel/vspace.c` 与 `arch/x86/64/kernel/vspace.c`；Zig 侧先提供 TLB 原语与 `vspace.zig` 常量。
pub const upstream_vspace_rel = "arch/x86/kernel/vspace.c";
pub const upstream_vspace_64_rel = "arch/x86/64/kernel/vspace.c";

const tlb = @import("tlb.zig");
pub const vspace = @import("vspace.zig");

pub const invlpg = tlb.invlpg;
