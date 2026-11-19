//! QEMU platform virtio transport wiring and DMA address translation.
pub const pci_mode = false;
pub const mmio_start: u64 = 0x0a000000;
pub const mmio_stride: u64 = 0x200;
pub const mmio_count: usize = 32;
pub fn physical(address: usize) u64 {
    return address;
}
