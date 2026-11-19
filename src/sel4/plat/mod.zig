//! Platform modules selected by the kernel build configuration.
pub const upstream_tree = "plat";

pub const pc99 = @import("pc99.zig");
pub const qemu_aarch64_virt = @import("qemu_aarch64_virt.zig");
pub const qemu_riscv64_virt = @import("qemu_riscv64_virt.zig");
pub const qemu_loongarch64_virt = @import("qemu_loongarch64_virt.zig");

// APIC and timer initialization still require a platform driver.
