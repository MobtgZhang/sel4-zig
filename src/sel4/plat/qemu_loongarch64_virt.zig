//! QEMU LoongArch `virt`：早期串口 MMIO 依 QEMU 版本而异；当前内核串口为桩（见 `serial_plat.zig`）。
pub const upstream_hint = "(无 seL4 上游 plat)";

pub const uart0_mmio_base: usize = 0;
