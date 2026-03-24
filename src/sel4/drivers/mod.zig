//! 官方驱动目录（相对外置 `src/drivers/`）。
pub const upstream_tree = "drivers";

/// QEMU / pc99 常用 COM1（与 `baremetal/serial_com1.zig` 端口一致）；完整驱动见 `drivers/serial/*.c`。
pub const com1_data_port: u16 = 0x3F8;
pub const com1_line_status_port: u16 = 0x3FD;

