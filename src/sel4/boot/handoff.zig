//! UEFI 与 Multiboot2 共用引导契约（计划阶段 B）。
const std = @import("std");
const phys_region = @import("../mm/phys_region.zig");

pub const PhysRegion = phys_region.PhysRegion;

/// `BootHandoff` 内必须用 ABI 稳定布局；与 `PhysRegion` 字段一致。
const HandoffPhysRegion = extern struct {
    start: u64,
    end: u64,
};

/// 魔数 ASCII `L4ZHAND1`（小端 u64）
pub const magic: u64 = blk: {
    const s: [8]u8 = "L4ZHAND1".*;
    break :blk std.mem.readInt(u64, &s, .little);
};

/// `flags & 1`：Multiboot2 路径下曾解析到 mmap；`flags & 2`：UEFI handoff（跳过 #PF 探测）；`flags & 4`：FDT（`mb2_phys` 存 DTB 指针）。
pub const flag_multiboot_mmap: u32 = 1;
pub const flag_uefi_handoff: u32 = 2;
pub const flag_fdt: u32 = 4;

pub const BootHandoff = extern struct {
    magic: u64,
    version: u32,
    flags: u32,
    /// Multiboot2 信息结构物理地址；UEFI 直达内核时为 0
    mb2_phys: u64,
    region_count: u32,
    _pad: u32 = 0,
    regions: [64]HandoffPhysRegion,
};

/// PVH / 无 MBI：单段可用 RAM（QEMU 常用 512MiB 以内 identity）
pub fn fillSyntheticLowRam(h: *BootHandoff, ram_end_exclusive: u64) void {
    h.* = .{
        .magic = magic,
        .version = 1,
        .flags = 0,
        .mb2_phys = 0,
        .region_count = 1,
        ._pad = 0,
        .regions = undefined,
    };
    h.regions[0] = .{ .start = 0, .end = ram_end_exclusive };
}

/// 自 Multiboot2 信息（`ebx` 物理指针）解析 mmap；失败时回退 synthetic。
pub fn fillFromMultiboot2(h: *BootHandoff, mb2_phys: u64) void {
    if (mb2_phys == 0) {
        fillSyntheticLowRam(h, 512 * 1024 * 1024);
        return;
    }
    const base: [*]const u8 = @ptrFromInt(mb2_phys);
    const total = std.mem.readInt(u32, base[0..4], .little);
    if (total < 16 or total > 0x100000) {
        fillSyntheticLowRam(h, 512 * 1024 * 1024);
        return;
    }

    h.* = .{
        .magic = magic,
        .version = 1,
        .flags = 0,
        .mb2_phys = mb2_phys,
        .region_count = 0,
        ._pad = 0,
        .regions = undefined,
    };

    var off: usize = 8;
    while (off + 8 <= total) {
        const tag_type = std.mem.readInt(u32, base[off..][0..4], .little);
        const tag_size = std.mem.readInt(u32, base[off + 4 ..][0..4], .little);
        if (tag_size < 8 or off + tag_size > total) break;
        if (tag_type == 0) break;

        if (tag_type == 6) {
            if (tag_size < 16 + @sizeOf(MmapEntry)) break;
            const esz = std.mem.readInt(u32, base[off + 8 ..][0..4], .little);
            const ver = std.mem.readInt(u32, base[off + 12 ..][0..4], .little);
            _ = ver;
            if (esz < @sizeOf(MmapEntry)) break;
            var eo: usize = off + 16;
            while (eo + esz <= off + tag_size) : (eo += esz) {
                const ent = std.mem.bytesToValue(MmapEntry, base[eo ..][0..@sizeOf(MmapEntry)]);
                if (ent.mmap_type == 1 and h.region_count < h.regions.len) {
                    h.regions[h.region_count] = .{
                        .start = ent.addr,
                        .end = ent.addr + ent.len,
                    };
                    h.region_count += 1;
                }
            }
        }

        off += std.mem.alignForward(usize, tag_size, 8);
    }

    if (h.region_count == 0) {
        fillSyntheticLowRam(h, 512 * 1024 * 1024);
    } else {
        h.flags |= flag_multiboot_mmap;
    }
}

const MmapEntry = extern struct {
    addr: u64,
    len: u64,
    mmap_type: u32,
    zero: u32,
};
