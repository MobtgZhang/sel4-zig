//! 最小设备树（FDT）解析：填充 `BootHandoff.regions`（对照上游 ARM/RISC-V `boot.c` 对 DTB 的用法）。
const std = @import("std");
const handoff = @import("handoff.zig");

const FDT_MAGIC: u32 = 0xd00dfeed;

const FDT_BEGIN_NODE: u32 = 0x00000001;
const FDT_END_NODE: u32 = 0x00000002;
const FDT_PROP: u32 = 0x00000003;
const FDT_NOP: u32 = 0x00000004;
const FDT_END: u32 = 0x00000009;

fn readBeU32(blob: []const u8, off: usize) ?u32 {
    if (off + 4 > blob.len) return null;
    return std.mem.readInt(u32, blob[off..][0..4], .big);
}

fn readPropName(strings: []const u8, nameoff: u32) []const u8 {
    const o: usize = @intCast(nameoff);
    if (o >= strings.len) return "";
    var end: usize = o;
    while (end < strings.len and strings[end] != 0) end += 1;
    return strings[o..end];
}

fn readNodeName(struct_blk: []const u8, start: *usize) ?[]const u8 {
    const name_start = start.*;
    var off = name_start;
    while (off < struct_blk.len and struct_blk[off] != 0) off += 1;
    if (off >= struct_blk.len) return null;
    const raw = struct_blk[name_start..off];
    off += 1;
    off = std.mem.alignForward(usize, off, 4);
    start.* = off;
    return raw;
}

fn isMemoryNode(name: []const u8) bool {
    return std.mem.eql(u8, name, "memory") or std.mem.startsWith(u8, name, "memory@");
}

fn isRootNode(name: []const u8) bool {
    return name.len == 0;
}

/// 自 DTB 物理地址填充 handoff；失败则 `fillSyntheticLowRam`。
pub fn fillFromFdt(h: *handoff.BootHandoff, fdt_phys: u64) void {
    if (fdt_phys == 0) {
        handoff.fillSyntheticLowRam(h, 512 * 1024 * 1024);
        return;
    }
    const blob: []const u8 = @as([*]const u8, @ptrFromInt(fdt_phys))[0..0x100000];

    const magic = readBeU32(blob, 0) orelse {
        handoff.fillSyntheticLowRam(h, 512 * 1024 * 1024);
        return;
    };
    if (magic != FDT_MAGIC) {
        handoff.fillSyntheticLowRam(h, 512 * 1024 * 1024);
        return;
    }

    const totalsize = readBeU32(blob, 4) orelse {
        handoff.fillSyntheticLowRam(h, 512 * 1024 * 1024);
        return;
    };
    if (totalsize > blob.len) {
        handoff.fillSyntheticLowRam(h, 512 * 1024 * 1024);
        return;
    }
    const full = blob[0..totalsize];

    const off_dt_struct = readBeU32(full, 8) orelse {
        handoff.fillSyntheticLowRam(h, 512 * 1024 * 1024);
        return;
    };
    const size_dt_struct = readBeU32(full, 12) orelse {
        handoff.fillSyntheticLowRam(h, 512 * 1024 * 1024);
        return;
    };
    const off_dt_strings = readBeU32(full, 16) orelse {
        handoff.fillSyntheticLowRam(h, 512 * 1024 * 1024);
        return;
    };
    const size_dt_strings = readBeU32(full, 20) orelse {
        handoff.fillSyntheticLowRam(h, 512 * 1024 * 1024);
        return;
    };

    if (off_dt_struct + size_dt_struct > full.len or off_dt_strings + size_dt_strings > full.len) {
        handoff.fillSyntheticLowRam(h, 512 * 1024 * 1024);
        return;
    }

    const struct_blk = full[off_dt_struct..][0..size_dt_struct];
    const strings_blk = full[off_dt_strings..][0..size_dt_strings];

    h.* = .{
        .magic = handoff.magic,
        .version = 1,
        .flags = handoff.flag_fdt,
        .mb2_phys = fdt_phys,
        .region_count = 0,
        ._pad = 0,
        .regions = undefined,
    };

    var addr_cells: u32 = 2;
    var size_cells: u32 = 2;

    var names: [16][]const u8 = undefined;
    var depth: usize = 0;

    var off: usize = 0;
    while (off + 4 <= struct_blk.len) {
        const token = readBeU32(struct_blk, off).?;
        off += 4;
        switch (token) {
            FDT_BEGIN_NODE => {
                if (depth >= names.len) return handoff.fillSyntheticLowRam(h, 512 * 1024 * 1024);
                const nm = readNodeName(struct_blk, &off) orelse return handoff.fillSyntheticLowRam(h, 512 * 1024 * 1024);
                names[depth] = nm;
                depth += 1;
            },
            FDT_END_NODE => {
                if (depth > 0) depth -= 1;
            },
            FDT_PROP => {
                const plen = readBeU32(struct_blk, off) orelse break;
                off += 4;
                const pnameoff = readBeU32(struct_blk, off) orelse break;
                off += 4;
                const pname = readPropName(strings_blk, pnameoff);
                if (off + plen > struct_blk.len) break;
                const pdata = struct_blk[off..][0..plen];
                off += plen;
                off = std.mem.alignForward(usize, off, 4);

                if (depth > 0) {
                    const cur = names[depth - 1];
                    if (isRootNode(cur)) {
                        if (std.mem.eql(u8, pname, "#address-cells") and plen >= 4) {
                            addr_cells = readBeU32(pdata, 0).?;
                        } else if (std.mem.eql(u8, pname, "#size-cells") and plen >= 4) {
                            size_cells = readBeU32(pdata, 0).?;
                        }
                    } else if (isMemoryNode(cur) and std.mem.eql(u8, pname, "reg")) {
                        appendRegRegions(h, pdata, addr_cells, size_cells);
                    }
                }
            },
            FDT_NOP => {},
            FDT_END => break,
            else => break,
        }
    }

    if (h.region_count == 0) {
        handoff.fillSyntheticLowRam(h, 512 * 1024 * 1024);
    }
}

fn appendRegRegions(h: *handoff.BootHandoff, reg: []const u8, ac: u32, sc: u32) void {
    const acs: usize = @intCast(ac);
    const scs: usize = @intCast(sc);
    const cell: usize = 4;
    const entry_len = (acs + scs) * cell;
    if (entry_len == 0 or reg.len < entry_len) return;

    var o: usize = 0;
    while (o + entry_len <= reg.len and h.region_count < h.regions.len) : (o += entry_len) {
        var base: u64 = 0;
        var i: usize = 0;
        while (i < acs) : (i += 1) {
            const w = readBeU32(reg, o + i * cell).?;
            base = (base << 32) | @as(u64, w);
        }
        var sz: u64 = 0;
        i = 0;
        while (i < scs) : (i += 1) {
            const w = readBeU32(reg, o + acs * cell + i * cell).?;
            sz = (sz << 32) | @as(u64, w);
        }
        if (sz == 0) continue;
        h.regions[h.region_count] = .{ .start = base, .end = base + sz };
        h.region_count += 1;
    }
}
