//! Four-level x86-64 page tables and a caller-owned mapping arena.
const std = @import("std");
pub const upstream_vspace_rel = "arch/x86/kernel/vspace.c";
pub const upstream_vspace_64_rel = "arch/x86/64/kernel/vspace.c";

pub const pte_present: u64 = 1 << 0;
pub const pte_rw: u64 = 1 << 1;
pub const pte_us: u64 = 1 << 2;
pub const pte_pwt: u64 = 1 << 3;
pub const pte_pcd: u64 = 1 << 4;
pub const pte_accessed: u64 = 1 << 5;
pub const pte_dirty: u64 = 1 << 6;
pub const pte_pat: u64 = 1 << 7;
pub const pte_global: u64 = 1 << 8;
pub const pte_nx: u64 = 1 << 63;

pub const page_shift: u6 = 12;
pub const page_size: u64 = 1 << page_shift;

/// Encode an aligned 4 KiB physical frame and supported hardware attributes.
pub fn pteFromPhys(phys_aligned: u64, flags: u64) u64 {
    return (phys_aligned & 0x000ffffffffff000) | (flags & (0xfff | pte_nx));
}

/// Level 0 is PT, 1 is PD, 2 is PDPT, and 3 is PML4.
pub fn virtPageTableIndex(virt: u64, level: u2) u9 {
    const shift: u6 = 12 + 9 * @as(u6, level);
    return @truncate((virt >> shift) & 0x1ff);
}

test "vspace pte 4k present+rw" {
    const p = pteFromPhys(0x1000, pte_present | pte_rw);
    try std.testing.expect((p & pte_present) != 0);
    try std.testing.expect((p & pte_rw) != 0);
    try std.testing.expectEqual(@as(u64, 0x1000), p & 0x000ffffffffff000);
}

test "vspace virt indices" {
    const v: u64 = @as(u64, 0x100) << 39;
    try std.testing.expectEqual(@as(u9, 0x100), virtPageTableIndex(v, 3));
    try std.testing.expectEqual(@as(u9, 0), virtPageTableIndex(v, 2));
}

test "PTE preserves the execute-disable permission" {
    try std.testing.expect(pteFromPhys(0x2000, pte_present | pte_nx) & pte_nx != 0);
}

pub const physical_mask: u64 = 0x000f_ffff_ffff_f000;
pub const huge: u64 = 1 << 7;
pub const Table = extern struct { entries: [512]u64 align(4096) };
pub const PageSize = enum(u6) { small = 12, large = 21, huge_page = 30 };
pub const MapError = error{ InvalidAddress, InvalidRights, AlreadyMapped, MissingMapping, TableConflict, OutOfTables, InvalidTable };

pub fn isCanonical(address: u64) bool {
    const top = address >> 47;
    return top == 0 or top == 0x1ffff;
}

/// Caller-owned page-table arena. Physical addresses need not equal Zig pointers.
/// Hardware users must invalidate local/remote TLBs after editing an active root.
pub const AddressSpace = struct {
    tables: []Table,
    physical_base: u64,
    used: [256]bool = @splat(false),

    pub fn init(tables: []Table, physical_base: u64) MapError!AddressSpace {
        if (tables.len == 0 or tables.len > 256 or physical_base & ~physical_mask != 0) return error.InvalidAddress;
        if (tables.len * 4096 - 1 > 0x000f_ffff_ffff_ffff - physical_base) return error.InvalidAddress;
        var self = AddressSpace{ .tables = tables, .physical_base = physical_base };
        self.used[0] = true;
        tables[0].entries = @splat(0);
        return self;
    }
    fn table(self: *AddressSpace, entry: u64) MapError!*Table {
        const physical = entry & physical_mask;
        if (physical < self.physical_base) return error.InvalidTable;
        const index = (physical - self.physical_base) / 4096;
        if (index >= self.tables.len or !self.used[@intCast(index)]) return error.InvalidTable;
        return &self.tables[@intCast(index)];
    }
    fn allocateTable(self: *AddressSpace) MapError!u64 {
        for (self.used[0..self.tables.len], 0..) |used, index| {
            if (used) continue;
            self.used[index] = true;
            self.tables[index].entries = @splat(0);
            return self.physical_base + index * 4096;
        }
        return error.OutOfTables;
    }
    fn freeCount(self: *const AddressSpace) usize {
        var count: usize = 0;
        for (self.used[0..self.tables.len]) |used| if (!used) {
            count += 1;
        };
        return count;
    }
    pub fn map(self: *AddressSpace, virtual: u64, physical: u64, size: PageSize, writable: bool, executable: bool, user_access: bool) MapError!void {
        const bits = @backingInt(size);
        const alignment = (@as(u64, 1) << bits) - 1;
        if (!isCanonical(virtual) or virtual & alignment != 0 or physical & alignment != 0 or physical & ~physical_mask != 0) return error.InvalidAddress;
        const target: u2 = switch (size) {
            .small => 0,
            .large => 1,
            .huge_page => 2,
        };
        // Preflight the entire walk so exhaustion cannot leave partial page tables.
        var current = &self.tables[0];
        var level: u2 = 3;
        var missing: usize = 0;
        while (level > target) : (level -= 1) {
            const entry = current.entries[virtPageTableIndex(virtual, level)];
            if (entry & pte_present == 0) {
                missing = @as(usize, level) - target;
                break;
            }
            if (entry & huge != 0) return error.TableConflict;
            current = try self.table(entry);
        }
        if (missing == 0 and current.entries[virtPageTableIndex(virtual, target)] & pte_present != 0) return error.AlreadyMapped;
        if (missing > self.freeCount()) return error.OutOfTables;
        current = &self.tables[0];
        level = 3;
        while (level > target) : (level -= 1) {
            const entry = &current.entries[virtPageTableIndex(virtual, level)];
            if (entry.* & pte_present == 0) entry.* = (try self.allocateTable()) | pte_present | pte_rw | pte_us;
            current = try self.table(entry.*);
        }
        current.entries[virtPageTableIndex(virtual, target)] = physical | pte_present |
            (if (writable) pte_rw else 0) | (if (user_access) pte_us else 0) |
            (if (executable) @as(u64, 0) else pte_nx) | (if (target != 0) huge else 0);
    }
    pub fn resolve(self: *AddressSpace, virtual: u64) MapError!struct { physical: u64, size: PageSize, writable: bool, executable: bool, user_access: bool } {
        if (!isCanonical(virtual)) return error.InvalidAddress;
        var current = &self.tables[0];
        var level: u2 = 3;
        var writable = true;
        var executable = true;
        var user_access = true;
        while (true) {
            const entry = current.entries[virtPageTableIndex(virtual, level)];
            if (entry & pte_present == 0) return error.MissingMapping;
            writable = writable and entry & pte_rw != 0;
            executable = executable and entry & pte_nx == 0;
            user_access = user_access and entry & pte_us != 0;
            if (level == 0 or (level < 3 and entry & huge != 0)) {
                const bits: u6 = 12 + 9 * @as(u6, level);
                const mask = (@as(u64, 1) << bits) - 1;
                return .{ .physical = (entry & physical_mask & ~mask) | (virtual & mask), .size = @fromBackingInt(@intCast(bits)), .writable = writable, .executable = executable, .user_access = user_access };
            }
            if (entry & huge != 0) return error.InvalidTable;
            current = try self.table(entry);
            level -= 1;
        }
    }
    pub fn mapPage(self: *AddressSpace, address: u64, physical: u64, writable: bool, executable: bool) !void {
        try self.map(address, physical, .small, writable, executable, true);
    }
    pub fn unmapPage(self: *AddressSpace, address: u64) !u64 {
        return self.unmap(address, .small);
    }
    pub fn activate(self: *AddressSpace) void {
        @import("machine.zig").writeCr3(self.physical_base);
    }
    pub fn unmap(self: *AddressSpace, virtual: u64, size: PageSize) MapError!u64 {
        if (!isCanonical(virtual) or virtual & ((@as(u64, 1) << @backingInt(size)) - 1) != 0) return error.InvalidAddress;
        const target: u2 = switch (size) {
            .small => 0,
            .large => 1,
            .huge_page => 2,
        };
        var tables: [4]*Table = undefined;
        tables[3] = &self.tables[0];
        var level: u2 = 3;
        while (level > target) : (level -= 1) {
            const entry = tables[level].entries[virtPageTableIndex(virtual, level)];
            if (entry & pte_present == 0) return error.MissingMapping;
            if (entry & huge != 0) return error.TableConflict;
            tables[level - 1] = try self.table(entry);
        }
        const leaf = &tables[target].entries[virtPageTableIndex(virtual, target)];
        if (leaf.* & pte_present == 0) return error.MissingMapping;
        if (target != 0 and leaf.* & huge == 0) return error.TableConflict;
        const physical = leaf.* & physical_mask;
        leaf.* = 0;
        level = target;
        while (level < 3) : (level += 1) {
            for (tables[level].entries) |entry| if (entry & pte_present != 0) return physical;
            const parent = &tables[level + 1].entries[virtPageTableIndex(virtual, level + 1)];
            const index = ((parent.* & physical_mask) - self.physical_base) / 4096;
            self.used[@intCast(index)] = false;
            parent.* = 0;
        }
        return physical;
    }
};

test "x86 address space maps all page sizes with permissions and reclaims tables" {
    var tables: [8]Table = undefined;
    var space = try AddressSpace.init(&tables, 0x100000);
    try space.map(0x4000, 0x8000, .small, false, false, true);
    const result = try space.resolve(0x4123);
    try std.testing.expectEqual(@as(u64, 0x8123), result.physical);
    try std.testing.expect(!result.writable and !result.executable and result.user_access);
    try std.testing.expectError(error.AlreadyMapped, space.map(0x4000, 0x9000, .small, true, true, true));
    try space.map(0x200000, 0x400000, .large, true, true, false);
    try std.testing.expectEqual(@as(u64, 0x400123), (try space.resolve(0x200123)).physical);
    try std.testing.expectError(error.TableConflict, space.map(0x201000, 0x9000, .small, true, true, true));
    try space.map(0x40000000, 0x80000000, .huge_page, true, false, true);
    try std.testing.expectEqual(@as(u64, 0x80000abc), (try space.resolve(0x40000abc)).physical);
    _ = try space.unmap(0x4000, .small);
    _ = try space.unmap(0x200000, .large);
    _ = try space.unmap(0x40000000, .huge_page);
    try std.testing.expectEqual(@as(usize, 7), space.freeCount());
    try std.testing.expectError(error.MissingMapping, space.resolve(0x4000));
}
test "x86 page table exhaustion is atomic and canonical addresses are enforced" {
    var tables: [3]Table = undefined;
    var space = try AddressSpace.init(&tables, 0x100000);
    try std.testing.expectError(error.OutOfTables, space.map(0x1000, 0x2000, .small, true, false, true));
    try std.testing.expectEqual(@as(u64, 0), tables[0].entries[0]);
    try std.testing.expectEqual(@as(usize, 2), space.freeCount());
    try std.testing.expectError(error.InvalidAddress, space.map(0x800000000000, 0x2000, .small, true, true, true));
    try space.map(0xffff800000000000, 0, .large, false, false, false);
    try std.testing.expectEqual(@as(u64, 42), (try space.resolve(0xffff80000000002a)).physical);
}
