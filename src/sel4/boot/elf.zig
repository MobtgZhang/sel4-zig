//! ELF64 multi-architecture image validation and bounded loading, independent of firmware.
//! Supports static ET_EXEC and self-contained ET_DYN with RELA relative relocations.
const std = @import("std");
const elf = std.elf;
pub const Error = error{ BadElf, BadPhdr, UnsupportedElf, UnsupportedRelocation, InvalidDestination };
fn range(bytes: []const u8, offset: u64, length: u64) Error![]const u8 {
    if (offset > bytes.len or length > bytes.len - offset) return error.BadElf;
    return bytes[@intCast(offset)..][0..@intCast(length)];
}
fn record(comptime T: type, bytes: []const u8, offset: u64) Error!T {
    return std.mem.bytesToValue(T, try range(bytes, offset, @sizeOf(T)));
}
fn add(a: u64, b: u64) Error!u64 {
    return std.math.add(u64, a, b) catch error.BadElf;
}
pub const Image = struct {
    bytes: []const u8,
    header: elf.Elf64.Ehdr,
    start: u64,
    end: u64,

    pub fn phdr(self: Image, index: usize) Error!elf.Elf64.Phdr {
        return record(elf.Elf64.Phdr, self.bytes, self.header.phoff + index * @as(u64, self.header.phentsize));
    }
    pub fn init(bytes: []const u8) Error!Image {
        return initFor(bytes, .X86_64);
    }
    pub fn initFor(bytes: []const u8, machine: elf.EM) Error!Image {
        const header = try record(elf.Elf64.Ehdr, bytes, 0);
        if (!std.mem.eql(u8, header.ident.magic[0..4], elf.MAGIC) or header.ident.class != .@"64" or header.ident.data != .@"2LSB" or header.ident.version != 1 or header.version != 1 or header.ehsize != @sizeOf(elf.Elf64.Ehdr)) return error.BadElf;
        if ((header.type != .DYN and header.type != .EXEC) or header.machine != machine) return error.UnsupportedElf;
        if (header.phnum == 0 or header.phnum > 128 or header.phentsize != @sizeOf(elf.Elf64.Phdr)) return error.BadPhdr;
        _ = try range(bytes, header.phoff, @as(u64, header.phnum) * header.phentsize);
        var self = Image{ .bytes = bytes, .header = header, .start = std.math.maxInt(u64), .end = 0 };
        var executable_entry = false;
        for (0..header.phnum) |i| {
            const ph = try self.phdr(i);
            if (ph.type == .INTERP) return error.UnsupportedElf;
            if (ph.type != .LOAD) continue;
            if (ph.filesz > ph.memsz) return error.BadPhdr;
            _ = try range(bytes, ph.offset, ph.filesz);
            if (ph.memsz == 0) continue;
            const end = try add(ph.vaddr, ph.memsz);
            if (ph.@"align" > 1 and (!std.math.isPowerOfTwo(ph.@"align") or ph.vaddr % ph.@"align" != ph.offset % ph.@"align")) return error.BadPhdr;
            for (0..i) |j| {
                const prev = try self.phdr(j);
                if (prev.type == .LOAD and prev.memsz != 0 and ph.vaddr < try add(prev.vaddr, prev.memsz) and prev.vaddr < end) return error.BadPhdr;
            }
            self.start = @min(self.start, ph.vaddr);
            self.end = @max(self.end, end);
            if (ph.flags.X and header.entry >= ph.vaddr and header.entry < end) executable_entry = true;
        }
        if (!executable_entry or self.start == std.math.maxInt(u64)) return error.BadPhdr;
        self.start = std.mem.alignBackward(u64, self.start, 4096);
        self.end = (try add(self.end, 4095)) & ~@as(u64, 4095);
        if (self.end - self.start > 64 * 1024 * 1024) return error.BadPhdr;
        return self;
    }
    pub fn size(self: Image) usize {
        return @intCast(self.end - self.start);
    }
    fn fileAtVirtual(self: Image, address: u64, length: u64) Error![]const u8 {
        for (0..self.header.phnum) |i| {
            const ph = try self.phdr(i);
            if (ph.type != .LOAD or address < ph.vaddr) continue;
            const offset = address - ph.vaddr;
            if (offset <= ph.filesz and length <= ph.filesz - offset) return range(self.bytes, ph.offset + offset, length);
        }
        return error.BadElf;
    }
    fn writableTarget(self: Image, address: u64) Error!void {
        for (0..self.header.phnum) |i| {
            const ph = try self.phdr(i);
            if (ph.type != .LOAD or !ph.flags.W or address < ph.vaddr) continue;
            const offset = address - ph.vaddr;
            if (offset <= ph.memsz and 8 <= ph.memsz - offset) return;
        }
        return error.BadElf;
    }
    pub fn load(self: Image, destination: []u8, physical: u64) Error!u64 {
        if (destination.len != self.size() or physical % 4096 != 0 or destination.len > std.math.maxInt(u64) - physical) return error.InvalidDestination;
        if (self.header.type == .EXEC and physical != self.start) return error.InvalidDestination;
        @memset(destination, 0);
        for (0..self.header.phnum) |i| {
            const ph = try self.phdr(i);
            if (ph.type != .LOAD or ph.memsz == 0) continue;
            const offset: usize = @intCast(ph.vaddr - self.start);
            @memcpy(destination[offset..][0..@intCast(ph.filesz)], try range(self.bytes, ph.offset, ph.filesz));
        }
        var dynamic_seen = false;
        for (0..self.header.phnum) |i| {
            const ph = try self.phdr(i);
            if (ph.type != .DYNAMIC) continue;
            if (dynamic_seen or ph.filesz % 16 != 0) return error.BadElf;
            dynamic_seen = true;
            const dynamic = try self.fileAtVirtual(ph.vaddr, ph.filesz);
            var address: u64 = 0;
            var length: u64 = 0;
            var stride: u64 = 24;
            var terminated = false;
            var offset: usize = 0;
            while (offset < dynamic.len) : (offset += 16) {
                const tag = std.mem.readInt(u64, dynamic[offset..][0..8], .little);
                const value = std.mem.readInt(u64, dynamic[offset + 8 ..][0..8], .little);
                switch (tag) {
                    0 => {
                        terminated = true;
                        break;
                    },
                    1, 17, 18, 19, 23, 35, 36, 37 => return error.UnsupportedRelocation,
                    7 => address = value,
                    8 => length = value,
                    9 => stride = value,
                    else => {},
                }
            }
            if (!terminated or stride != 24 or length % 24 != 0) return error.BadElf;
            if (length == 0) continue;
            const relocations = try self.fileAtVirtual(address, length);
            offset = 0;
            while (offset < relocations.len) : (offset += 24) {
                const rela = try record(elf.Elf64.Rela, relocations, offset);
                if (@as(u64, @bitCast(rela.info)) == 0) continue;
                if (@as(u64, @bitCast(rela.info)) != switch (self.header.machine) {
                    .X86_64 => @as(u64, 8),
                    .AARCH64 => 1027,
                    .RISCV => 3,
                    .LOONGARCH => 3,
                    else => return error.UnsupportedElf,
                }) return error.UnsupportedRelocation;
                try self.writableTarget(rela.offset);
                const target: usize = @intCast(rela.offset - self.start);
                const addend: u64 = @bitCast(rela.addend);
                std.mem.writeInt(u64, destination[target..][0..8], addend +% (physical -% self.start), .little);
            }
        }
        return physical + (self.header.entry - self.start);
    }
};

test "ELF bounds reject truncated headers and overflowing program tables" {
    try std.testing.expectError(error.BadElf, Image.init("\x7fELF"));
    var header: elf.Elf64.Ehdr = std.mem.zeroes(elf.Elf64.Ehdr);
    @memcpy(header.ident.magic[0..4], elf.MAGIC);
    header.ident.class = .@"64";
    header.ident.data = .@"2LSB";
    header.ident.version = 1;
    header.version = 1;
    header.ehsize = @sizeOf(elf.Elf64.Ehdr);
    header.type = .DYN;
    header.machine = .X86_64;
    header.phnum = 1;
    header.phentsize = @sizeOf(elf.Elf64.Phdr);
    header.phoff = std.math.maxInt(u64);
    try std.testing.expectError(error.BadElf, Image.init(std.mem.asBytes(&header)));
}

test "PIE loader relocates writable data and rejects out-of-image writes" {
    var bytes: [1024]u8 = @splat(0);
    var hdr: elf.Elf64.Ehdr = std.mem.zeroes(elf.Elf64.Ehdr);
    @memcpy(hdr.ident.magic[0..4], elf.MAGIC);
    hdr.ident.class = .@"64";
    hdr.ident.data = .@"2LSB";
    hdr.ident.version = 1;
    hdr.version = 1;
    hdr.ehsize = @sizeOf(elf.Elf64.Ehdr);
    hdr.type = .DYN;
    hdr.machine = .X86_64;
    hdr.phnum = 3;
    hdr.phentsize = @sizeOf(elf.Elf64.Phdr);
    hdr.phoff = 64;
    hdr.entry = 0x400100;
    @memcpy(bytes[0..64], std.mem.asBytes(&hdr));
    var ph: elf.Elf64.Phdr = std.mem.zeroes(elf.Elf64.Phdr);
    ph.type = .LOAD;
    ph.flags = .{ .R = true, .X = true };
    ph.offset = 0x100;
    ph.vaddr = 0x400100;
    ph.filesz = 0x10;
    ph.memsz = 0x100;
    @memcpy(bytes[64..120], std.mem.asBytes(&ph));
    ph.flags = .{ .R = true, .W = true };
    ph.offset = 0x200;
    ph.vaddr = 0x401000;
    ph.filesz = 0x100;
    ph.memsz = 0x200;
    @memcpy(bytes[120..176], std.mem.asBytes(&ph));
    ph.type = .DYNAMIC;
    ph.filesz = 64;
    @memcpy(bytes[176..232], std.mem.asBytes(&ph));
    const dynamic = [_]u64{ 7, 0x401050, 8, 24, 9, 24, 0, 0 };
    for (dynamic, 0..) |value, i| std.mem.writeInt(u64, bytes[0x200 + i * 8 ..][0..8], value, .little);
    std.mem.writeInt(u64, bytes[0x250..0x258], 0x401100, .little);
    std.mem.writeInt(u64, bytes[0x258..0x260], 8, .little);
    std.mem.writeInt(u64, bytes[0x260..0x268], 0x400100, .little);
    bytes[0x100] = 0xc3;
    const image = try Image.init(&bytes);
    var destination: [8192]u8 = undefined;
    const entry = try image.load(&destination, 0x800000);
    try std.testing.expectEqual(@as(u64, 0x800100), entry);
    try std.testing.expectEqual(@as(u8, 0xc3), destination[0x100]);
    try std.testing.expectEqual(@as(u64, 0x800100), std.mem.readInt(u64, destination[0x1100..0x1108], .little));
    try std.testing.expectEqual(@as(u8, 0), destination[0x11ff]);
    std.mem.writeInt(u64, bytes[0x250..0x258], 0x500000, .little);
    try std.testing.expectError(error.BadElf, image.load(&destination, 0x800000));
    std.mem.writeInt(u64, bytes[0x250..0x258], 0x401100, .little);
    std.mem.writeInt(u64, bytes[0x258..0x260], 1, .little);
    try std.testing.expectError(error.UnsupportedRelocation, image.load(&destination, 0x800000));
}

test "high virtual ELF link address rebases without intermediate overflow" {
    var bytes: [256]u8 = @splat(0);
    var hdr: elf.Elf64.Ehdr = std.mem.zeroes(elf.Elf64.Ehdr);
    @memcpy(hdr.ident.magic[0..4], elf.MAGIC);
    hdr.ident.class = .@"64";
    hdr.ident.data = .@"2LSB";
    hdr.ident.version = 1;
    hdr.version = 1;
    hdr.ehsize = @sizeOf(elf.Elf64.Ehdr);
    hdr.type = .DYN;
    hdr.machine = .X86_64;
    hdr.phnum = 1;
    hdr.phentsize = @sizeOf(elf.Elf64.Phdr);
    hdr.phoff = 64;
    hdr.entry = 0xffffffff80000080;
    @memcpy(bytes[0..64], std.mem.asBytes(&hdr));
    var ph: elf.Elf64.Phdr = std.mem.zeroes(elf.Elf64.Phdr);
    ph.type = .LOAD;
    ph.flags = .{ .R = true, .X = true };
    ph.vaddr = 0xffffffff80000000;
    ph.filesz = bytes.len;
    ph.memsz = 4096;
    @memcpy(bytes[64..120], std.mem.asBytes(&ph));
    const image = try Image.init(&bytes);
    var destination: [4096]u8 = undefined;
    try std.testing.expectEqual(@as(u64, 0x800080), try image.load(&destination, 0x800000));
}
