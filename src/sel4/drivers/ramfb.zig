//! Native QEMU ramfb scanout programming through fw_cfg DMA after firmware exit.
//! ramfb is a platform display device; it does not implement legacy VGA registers.
const std = @import("std");
const Descriptor = @import("framebuffer.zig").Descriptor;
pub const display_kind = .native_ramfb;
var configuration: [28]u8 align(8) = @splat(0);
pub fn configure(inherited: Descriptor) !Descriptor {
    try inherited.validate();
    const fourcc: u32 = if (inherited.red_mask == 0xff0000 and inherited.green_mask == 0xff00 and inherited.blue_mask == 0xff)
        0x34325258 // DRM_FORMAT_XRGB8888
    else if (inherited.red_mask == 0xff and inherited.green_mask == 0xff00 and inherited.blue_mask == 0xff0000)
        0x34324258 // DRM_FORMAT_XBGR8888
    else
        return error.UnsupportedRamfbFormat;
    // Reuse the reserved aperture, so no firmware allocation is needed or freed.
    std.mem.writeInt(u64, configuration[0..8], inherited.address, .big);
    std.mem.writeInt(u32, configuration[8..12], fourcc, .big);
    std.mem.writeInt(u32, configuration[12..16], 0, .big);
    std.mem.writeInt(u32, configuration[16..20], inherited.width, .big);
    std.mem.writeInt(u32, configuration[20..24], inherited.height, .big);
    std.mem.writeInt(u32, configuration[24..28], inherited.stride * 4, .big);
    try @import("fw_cfg.zig").writeFile("etc/ramfb", &configuration);
    return inherited;
}
