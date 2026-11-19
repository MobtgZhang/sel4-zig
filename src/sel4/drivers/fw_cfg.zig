//! QEMU fw_cfg MMIO directory and synchronous DMA writes, without EFI callbacks.
const std = @import("std");
const arch = @import("../arch/mod.zig").backend;
const io = @import("../platform/io.zig");
const base = arch.fw_cfg_base;
var dma: [16]u8 align(16) = @splat(0);
var unavailable = false;
fn select(key: u16) void {
    io.write(u16, base + 8, @byteSwap(key));
}
fn read(bytes: []u8) void {
    for (bytes) |*byte| byte.* = io.read(u8, base);
}
fn find(name: []const u8, length: usize) !u16 {
    var bytes: [64]u8 = undefined;
    select(0);
    read(bytes[0..4]);
    if (!std.mem.eql(u8, bytes[0..4], "QEMU")) return error.NoFwCfg;
    select(1);
    read(bytes[0..4]);
    if (std.mem.readInt(u32, bytes[0..4], .little) & 2 == 0) return error.NoFwCfgDma;
    select(0x19);
    read(bytes[0..4]);
    const count = std.mem.readInt(u32, bytes[0..4], .big);
    if (count > 4096) return error.InvalidFwCfgDirectory;
    for (0..count) |_| {
        read(&bytes);
        const end = std.mem.indexOfScalar(u8, bytes[8..], 0) orelse return error.InvalidFwCfgDirectory;
        if (std.mem.eql(u8, bytes[8..][0..end], name)) {
            if (std.mem.readInt(u32, bytes[0..4], .big) != length) return error.InvalidFwCfgFile;
            return std.mem.readInt(u16, bytes[4..6], .big);
        }
    }
    return error.FwCfgFileNotFound;
}
/// The caller retains the DMA buffer even if the device stops responding.
pub fn writeFile(name: []const u8, bytes: []const u8) !void {
    if (unavailable) return error.FwCfgNeedsReset;
    const key = try find(name, bytes.len);
    std.mem.writeInt(u32, dma[0..4], (@as(u32, key) << 16) | 0x18, .big);
    std.mem.writeInt(u32, dma[4..8], @intCast(bytes.len), .big);
    std.mem.writeInt(u64, dma[8..16], arch.virtio.physical(@intFromPtr(bytes.ptr)), .big);
    arch.dmaBarrier();
    io.write(u64, base + 16, @byteSwap(arch.virtio.physical(@intFromPtr(&dma))));
    const control: *volatile u32 = @ptrCast(&dma);
    for (0..1_000_000) |_| {
        const value = @byteSwap(control.*);
        if (value == 0) {
            arch.dmaBarrier();
            return;
        }
        if (value & 1 != 0) return error.FwCfgDmaFailed;
        arch.relax();
    }
    unavailable = true;
    return error.FwCfgDmaTimeout;
}
