//! 将本仓库 `kernel-uefi.elf` 载入物理地址并 `ExitBootServices` 后跳入 `kmain(handoff_phys)`。
const std = @import("std");
const uefi = std.os.uefi;
const elf = std.elf;
const handoff_mod = @import("../sel4/boot/handoff.zig");
const phys_region = @import("../sel4/mm/phys_region.zig");

fn applyPieRelaDyn(
    file_buf: []const u8,
    hdr: elf.Elf64_Ehdr,
    base_phys: u64,
    region_lo: u64,
) !void {
    if (hdr.e_shoff == 0 or hdr.e_shentsize < @sizeOf(elf.Elf64_Shdr)) return;
    if (hdr.e_shstrndx == elf.SHN_UNDEF) return;

    const shstr_entry_off = @as(usize, @intCast(hdr.e_shoff)) + @as(usize, @intCast(hdr.e_shstrndx)) * @as(usize, @intCast(hdr.e_shentsize));
    if (shstr_entry_off + @sizeOf(elf.Elf64_Shdr) > file_buf.len) return error.BadElf;
    const shstr_sh = std.mem.bytesToValue(elf.Elf64_Shdr, file_buf[shstr_entry_off..][0..@sizeOf(elf.Elf64_Shdr)]);
    const shstrtab = file_buf[@intCast(shstr_sh.sh_offset)..][0..@intCast(shstr_sh.sh_size)];

    var si: u16 = 0;
    while (si < hdr.e_shnum) : (si += 1) {
        const soff = @as(usize, @intCast(hdr.e_shoff)) + @as(usize, @intCast(si)) * @as(usize, @intCast(hdr.e_shentsize));
        if (soff + @sizeOf(elf.Elf64_Shdr) > file_buf.len) return error.BadElf;
        const sh = std.mem.bytesToValue(elf.Elf64_Shdr, file_buf[soff..][0..@sizeOf(elf.Elf64_Shdr)]);
        if (sh.sh_type != elf.SHT_RELA) continue;
        const sn = shstrtab[@intCast(sh.sh_name)..];
        const name = std.mem.sliceTo(sn, 0);
        if (!std.mem.eql(u8, name, ".rela.dyn")) continue;

        if (sh.sh_entsize < @sizeOf(elf.Elf64_Rela)) return error.BadElf;
        const delta = base_phys -% region_lo;
        var ro: u64 = 0;
        while (ro < sh.sh_size) : (ro += sh.sh_entsize) {
            const rela_off = @as(usize, @intCast(sh.sh_offset + ro));
            if (rela_off + @sizeOf(elf.Elf64_Rela) > file_buf.len) return error.BadElf;
            const rela = std.mem.bytesToValue(elf.Elf64_Rela, file_buf[rela_off..][0..@sizeOf(elf.Elf64_Rela)]);
            const r_type: u32 = @truncate(rela.r_info);
            if (r_type != @intFromEnum(elf.R_X86_64.RELATIVE)) continue;
            const tgt: *u64 = @ptrFromInt(base_phys + (rela.r_offset - region_lo));
            const add: u64 = @bitCast(rela.r_addend);
            tgt.* = add +% delta;
        }
        return;
    }
}

/// 半开区间 [a, b) 与 [c, d) 是否相交。
fn rangesOverlap(a: u64, b: u64, c: u64, d: u64) bool {
    return a < d and c < b;
}

fn exitBootServicesWithRetry(bs: *uefi.tables.BootServices) !void {
    var mmap_buf: [65536]u8 align(@alignOf(uefi.tables.MemoryDescriptor)) = undefined;
    for (0..128) |_| {
        const map = try bs.getMemoryMap(@as([]align(@alignOf(uefi.tables.MemoryDescriptor)) u8, &mmap_buf));
        bs.exitBootServices(uefi.handle, map.info.key) catch {
            continue;
        };
        return;
    }
    return error.ExitBootServicesFailed;
}

fn loadElfSegments(bs: *uefi.tables.BootServices, file_buf: []const u8) !struct { hdr: elf.Elf64_Ehdr, entry: u64, load_min: u64, load_end: u64 } {
    if (file_buf.len < @sizeOf(elf.Elf64_Ehdr)) return error.BadElf;
    const hdr = std.mem.bytesToValue(elf.Elf64_Ehdr, file_buf[0..@sizeOf(elf.Elf64_Ehdr)]);
    if (!std.mem.eql(u8, hdr.e_ident[0..4], elf.MAGIC)) return error.BadElf;
    if (hdr.e_ident[elf.EI_CLASS] != elf.ELFCLASS64) return error.Not64;
    if (hdr.e_type != .EXEC and hdr.e_type != .DYN) return error.NotExec;
    if (hdr.e_machine != .X86_64) return error.NotX86_64;
    if (hdr.e_phoff == 0 or hdr.e_phnum == 0) return error.NoPhdr;
    if (hdr.e_phentsize < @sizeOf(elf.Elf64_Phdr)) return error.BadPhdr;

    var vmin: u64 = std.math.maxInt(u64);
    var vmax: u64 = 0;
    var i: u16 = 0;
    while (i < hdr.e_phnum) : (i += 1) {
        const off = @as(usize, @intCast(hdr.e_phoff)) + @as(usize, @intCast(i)) * @as(usize, @intCast(hdr.e_phentsize));
        if (off + @sizeOf(elf.Elf64_Phdr) > file_buf.len) return error.BadPhdr;
        const ph = std.mem.bytesToValue(elf.Elf64_Phdr, file_buf[off..][0..@sizeOf(elf.Elf64_Phdr)]);
        if (ph.p_type != elf.PT_LOAD) continue;
        if (ph.p_memsz == 0) continue;
        const lo = ph.p_vaddr;
        const hi = ph.p_vaddr + ph.p_memsz;
        vmin = @min(vmin, lo);
        vmax = @max(vmax, hi);
    }
    if (vmin == std.math.maxInt(u64)) return error.NoPhdr;

    const region_lo = std.mem.alignBackward(u64, vmin, 4096);
    const region_hi = std.mem.alignForward(u64, vmax, 4096);
    const total_bytes = region_hi - region_lo;
    const n_pages: usize = @intCast(total_bytes / 4096);
    if (n_pages == 0) return error.BadPhdr;

    const pages = try bs.allocatePages(.{ .any = {} }, .loader_data, n_pages);
    const base_phys: u64 = @intFromPtr(pages.ptr);
    const dst_all: [*]u8 = @ptrCast(pages.ptr);
    @memset(dst_all[0 .. n_pages * 4096], 0);

    i = 0;
    while (i < hdr.e_phnum) : (i += 1) {
        const off = @as(usize, @intCast(hdr.e_phoff)) + @as(usize, @intCast(i)) * @as(usize, @intCast(hdr.e_phentsize));
        if (off + @sizeOf(elf.Elf64_Phdr) > file_buf.len) return error.BadPhdr;
        const ph = std.mem.bytesToValue(elf.Elf64_Phdr, file_buf[off..][0..@sizeOf(elf.Elf64_Phdr)]);
        if (ph.p_type != elf.PT_LOAD) continue;
        if (ph.p_memsz == 0) continue;

        const seg_off = @as(usize, @intCast(ph.p_vaddr - region_lo));
        const dst = dst_all + seg_off;
        if (ph.p_filesz > 0) {
            const foff = @as(usize, @intCast(ph.p_offset));
            const fsz = @as(usize, @intCast(ph.p_filesz));
            if (foff + fsz > file_buf.len) return error.BadElf;
            const in_file = file_buf[foff..][0..fsz];
            if (seg_off + in_file.len > n_pages * 4096) return error.BadElf;
            @memcpy(dst[0..in_file.len], in_file);
        }
    }

    if (hdr.e_type == .DYN) {
        try applyPieRelaDyn(file_buf, hdr, base_phys, region_lo);
    }

    const entry = base_phys + (hdr.e_entry - region_lo);
    const load_end = base_phys + n_pages * 4096;
    return .{ .hdr = hdr, .entry = entry, .load_min = base_phys, .load_end = load_end };
}

fn tryOpenKernel(root: *uefi.protocol.File) ?*uefi.protocol.File {
    const paths = [_][*:0]const u16{
        std.unicode.utf8ToUtf16LeStringLiteral("\\KERNEL.ELF"),
        std.unicode.utf8ToUtf16LeStringLiteral("KERNEL.ELF"),
        std.unicode.utf8ToUtf16LeStringLiteral("kernel-uefi.elf"),
        std.unicode.utf8ToUtf16LeStringLiteral("\\kernel-uefi.elf"),
        std.unicode.utf8ToUtf16LeStringLiteral("\\EFI\\BOOT\\kernel-uefi.elf"),
        std.unicode.utf8ToUtf16LeStringLiteral("\\EFI\\BOOT\\KERNEL-UEFI.ELF"),
        std.unicode.utf8ToUtf16LeStringLiteral("\\EFI\\BOOT\\KERN.ELF"),
        std.unicode.utf8ToUtf16LeStringLiteral("EFI\\BOOT\\KERN.ELF"),
    };
    for (paths) |p| {
        const f = root.open(p, .read, .{}) catch continue;
        return f;
    }
    return null;
}

/// 成功则永不返回；失败返回以便调用方继续 idle。
pub fn loadHandoffAndJumpToKernel(
    bs: *uefi.tables.BootServices,
    pregions: []const phys_region.PhysRegion,
) !void {
    const hlist = (try bs.locateHandleBuffer(.{ .by_protocol = &uefi.protocol.SimpleFileSystem.guid })) orelse return error.NoSimpleFs;
    defer _ = bs.freePool(@alignCast(@ptrCast(hlist.ptr))) catch {};

    var kfile: *uefi.protocol.File = undefined;
    var vol_root: *uefi.protocol.File = undefined;
    var found = false;

    for (hlist) |hv| {
        const sfsp = bs.openProtocol(uefi.protocol.SimpleFileSystem, hv, .{ .by_handle_protocol = .{} }) catch continue;
        const sfs = sfsp orelse continue;
        const vol = sfs.openVolume() catch continue;
        if (tryOpenKernel(vol)) |kf| {
            kfile = kf;
            vol_root = vol;
            found = true;
            break;
        }
        _ = vol.close() catch {};
    }

    if (!found) return error.NoKernelElf;

    defer _ = kfile.close() catch {};
    defer _ = vol_root.close() catch {};

    const info_sz = try kfile.getInfoSize(.file);
    const info_buf = try bs.allocatePool(.loader_data, info_sz);
    defer _ = bs.freePool(info_buf.ptr) catch {};
    const finfo = try kfile.getInfo(.file, info_buf);
    const fsize: usize = @intCast(finfo.file_size);
    if (fsize < 512 or fsize > 32 * 1024 * 1024) return error.BadKernelSize;

    const file_buf = try bs.allocatePool(.loader_data, fsize);
    defer _ = bs.freePool(file_buf.ptr) catch {};

    var read_pos: usize = 0;
    while (read_pos < fsize) {
        const n = try kfile.read(file_buf[read_pos..]);
        if (n == 0) return error.ReadFailed;
        read_pos += n;
    }

    // 必须先加载内核映像再分配 BootHandoff：否则 loadElf 对映像整段 memset 可能与已分配的 handoff 页物理重叠，擦掉 magic。
    const loaded = try loadElfSegments(bs, file_buf);

    const ho_size = @sizeOf(handoff_mod.BootHandoff);
    comptime {
        std.debug.assert(ho_size <= 4096);
    }
    const ho_pages: usize = 1;

    const ho: *handoff_mod.BootHandoff = ho_blk: {
        for (0..128) |_| {
            const pages = try bs.allocatePages(.{ .any = {} }, .runtime_services_data, ho_pages);
            const ho_addr = @intFromPtr(pages.ptr);
            const ho_end = ho_addr + ho_pages * 4096;
            if (rangesOverlap(ho_addr, ho_end, loaded.load_min, loaded.load_end)) {
                bs.freePages(pages) catch {};
                continue;
            }
            break :ho_blk @ptrCast(pages.ptr);
        }
        return error.HandoffAllocFailed;
    };

    @memset(@as([*]u8, @ptrCast(ho))[0..ho_size], 0);
    ho.* = .{
        .magic = handoff_mod.magic,
        .version = 1,
        .flags = handoff_mod.flag_uefi_handoff,
        .mb2_phys = 0,
        .region_count = @intCast(@min(pregions.len, ho.regions.len)),
        ._pad = 0,
        .regions = undefined,
    };
    const n = ho.region_count;
    for (0..n) |j| {
        ho.regions[j] = .{ .start = pregions[j].start, .end = pregions[j].end };
    }

    try exitBootServicesWithRetry(bs);

    asm volatile ("cli");
    const entry: *const fn (u64) callconv(.c) noreturn = @ptrFromInt(loaded.entry);
    entry(@intFromPtr(ho));
}
