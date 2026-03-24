//! 镜像（复杂逻辑保留 C）：`seL4/src/kernel/cspace.c`
pub const upstream_rel = "kernel/cspace.c";

pub const migration_phase: u8 = 0;

pub fn lookupCapSlotStub(_: u64, _: u64) u8 {
    return 0;
}
