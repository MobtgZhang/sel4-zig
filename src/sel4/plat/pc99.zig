//! Legacy PC platform constants; reference src/plat/pc99/machine.
pub const upstream_ioapic_rel = "plat/pc99/machine/ioapic.c";
pub const upstream_pic_rel = "plat/pc99/machine/pic.c";
pub const upstream_pit_rel = "plat/pc99/machine/pit.c";
pub const upstream_hardware_rel = "plat/pc99/machine/hardware.c";

/// Default QEMU I/O APIC MMIO base.
pub const ioapic_mmio_base: u32 = 0xFEC00000;
/// Default local APIC MMIO base.
pub const local_apic_mmio_base: u32 = 0xFEE00000;
