//! 对照外置 `seL4/src/plat/pc99/machine/`（QEMU pc99 / 传统 PC）。
pub const upstream_ioapic_rel = "plat/pc99/machine/ioapic.c";
pub const upstream_pic_rel = "plat/pc99/machine/pic.c";
pub const upstream_pit_rel = "plat/pc99/machine/pit.c";
pub const upstream_hardware_rel = "plat/pc99/machine/hardware.c";

/// 典型 x86 I/O APIC MMIO 默认基址（与 QEMU ich9-ioapic 一致）。
pub const ioapic_mmio_base: u32 = 0xFEC00000;
/// Local APIC 默认 MMIO 基址。
pub const local_apic_mmio_base: u32 = 0xFEE00000;

pub fn initStub() void {}
