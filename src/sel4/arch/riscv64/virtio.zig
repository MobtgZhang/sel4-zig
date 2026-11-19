//! QEMU platform virtio transport wiring and DMA address translation.
pub const pci_mode = false;
pub const mmio_start: u64 = 0x10001000;
pub const mmio_stride: u64 = 0x1000;
pub const mmio_count: usize = 8;
pub fn physical(address: usize) u64 {
    return address;
}
