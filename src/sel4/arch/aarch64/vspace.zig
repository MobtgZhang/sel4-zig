//! 对照 `arch/arm/64/kernel/vspace.c`。
pub const upstream_rel = "arch/arm/64/kernel/vspace.c";

pub fn ptePresentStub() bool {
    return true;
}
