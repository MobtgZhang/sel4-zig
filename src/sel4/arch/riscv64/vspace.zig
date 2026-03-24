//! 对照 `arch/riscv/kernel/vspace.c`。
pub const upstream_rel = "arch/riscv/kernel/vspace.c";

pub fn ptePresentStub() bool {
    return true;
}
