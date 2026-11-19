//! QEMU platform virtio transport wiring and DMA address translation.
pub const pci_mode = true;
pub const pci = @import("pci.zig");
pub fn physical(address: usize) u64 {
    return address;
}
