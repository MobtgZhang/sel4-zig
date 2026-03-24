//! 官方平台层（相对外置 `src/plat/`）；多架构 QEMU 平台常量见各子模块。
pub const upstream_tree = "plat";

pub const pc99 = @import("pc99.zig");
pub const qemu_aarch64_virt = @import("qemu_aarch64_virt.zig");
pub const qemu_riscv64_virt = @import("qemu_riscv64_virt.zig");
pub const qemu_loongarch64_virt = @import("qemu_loongarch64_virt.zig");

// APIC/定时器：完整逻辑仍在上游 `plat/pc99/machine/*.c`。
pub const apic_placeholder = true;
