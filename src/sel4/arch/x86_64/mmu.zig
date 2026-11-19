//! x86 memory-management primitives and native page-table operations.
pub const upstream_vspace_rel = "arch/x86/kernel/vspace.c";
pub const upstream_vspace_64_rel = "arch/x86/64/kernel/vspace.c";

const tlb = @import("tlb.zig");
pub const vspace = @import("vspace.zig");

pub const invlpg = tlb.invlpg;
