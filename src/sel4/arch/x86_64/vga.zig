//! Native QEMU standard VGA/Bochs VBE driver. No BIOS or UEFI calls are used.
//! This device is specific to x86 PC machines, not QEMU's virt ramfb device.
const framebuffer = @import("../../drivers/framebuffer.zig");
pub const display_kind = .native_vga;
const pci = @import("pci.zig");

fn read(index: u16) u16 {
    pci.write(u16, 0x1ce, index);
    return pci.read(u16, 0x1cf);
}
fn write(index: u16, value: u16) void {
    pci.write(u16, 0x1ce, index);
    pci.write(u16, 0x1cf, value);
}

/// Reuse only a validated, already mapped PCI aperture from the boot handoff.
/// Changing scanout is owned by the kernel after ExitBootServices.
pub fn configure(inherited: framebuffer.Descriptor) !framebuffer.Descriptor {
    try inherited.validate();
    var slot: ?u8 = null;
    for (0..32) |index| {
        const candidate: u8 = @intCast(index);
        if (pci.configRead(candidate, 0) == 0x11111234) {
            slot = candidate;
            break;
        }
    }
    const device = slot orelse return error.NoNativeVga;
    const bar = pci.configRead(device, 0x10);
    if (bar & 1 != 0 or bar & 6 != 0 or @as(u64, bar & 0xfffffff0) != inherited.address) return error.UnsupportedVgaAperture;
    const version = read(0);
    if (version < 0xb0c2 or version > 0xb0c5) return error.UnsupportedVgaVersion;
    const bytes = @as(u64, read(10)) * 65536;
    const width: u16 = @intCast(inherited.width);
    const height: u16 = @intCast(inherited.height);
    if (bytes < @as(u64, width) * height * 4) return error.SmallVgaAperture;
    write(4, 0);
    write(1, width);
    write(2, height);
    write(3, 32);
    write(6, width);
    write(8, 0);
    write(9, 0);
    write(4, 0x41); // Enable scanout and linear framebuffer addressing.
    if (read(1) != width or read(2) != height or read(3) != 32 or read(4) & 0x41 != 0x41) return error.VgaModeRejected;
    return .{ .address = inherited.address, .byte_size = inherited.byte_size, .width = width, .height = height, .stride = width, .red_mask = 0xff0000, .green_mask = 0xff00, .blue_mask = 0xff };
}
