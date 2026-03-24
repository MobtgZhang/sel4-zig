//! 对照 `seL4/src/machine/registerset.c`、`arch/x86/machine/registerset.c`、`arch/x86/64/machine/registerset.c`。
pub const upstream_rel = "machine/registerset.c";
pub const upstream_arch_rel = "arch/x86/machine/registerset.c";
pub const upstream_arch_64_rel = "arch/x86/64/machine/registerset.c";

pub fn saveUserRegsStub() void {}
