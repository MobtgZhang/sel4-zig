//! 对照上游 `src/plat/*/qemu-arm-virt` 等平台树中的 `hardware.c` / 设备基址。
pub const upstream_hint = "plat/qemu-arm-virt（或等价 ARM QEMU virt preset）";

/// PL011 UART（与 `baremetal/serial_plat.zig` 一致）
pub const uart0_mmio_base: usize = 0x9000000;
