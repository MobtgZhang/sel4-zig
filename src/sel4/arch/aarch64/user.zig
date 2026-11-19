//! ARMv8-A EL0 contexts and four-level 4 KiB stage-1 translation.
const std = @import("std");
const Call = @import("../user_call.zig").Call;
pub const Table = extern struct { entries: [512]u64 = @splat(0) };
pub const Frame = extern struct {
    regs: [31]u64 = @splat(0),
    sp: u64 = 0,
    pc: u64 = 0,
    status: u64 = 0x340,
    fp: [64]u64 = @splat(0),
    fpcr: u64 = 0,
    fpsr: u64 = 0,
};
comptime {
    std.debug.assert(@sizeOf(Frame) == 800);
}
extern fn arch_user_restore(*const Frame) callconv(.c) noreturn;
extern fn arch_user_vector() void;
const mask: u64 = 0x0000fffffffff000;
pub const Space = struct {
    tables: []Table,
    used: usize = 1,
    pub fn init(tables: []Table) !Space {
        @memset(std.mem.sliceAsBytes(tables), 0);
        var self: Space = .{ .tables = tables };
        const l1 = try self.child(0, 0);
        // Normal cacheable RAM; EL0 cannot access this identity mapping.
        self.tables[l1].entries[1] = 0x40000000 | 1 | (1 << 10) | (3 << 8) | (1 << 54);
        try self.mapKernel(0x09000000, 0x09000000);
        try self.mapKernel(0x08000000, 0x08000000);
        try self.mapKernel(0x08010000, 0x08010000);
        for (0..4) |i| try self.mapKernel(0x0a000000 + i * 4096, 0x0a000000 + i * 4096);
        return self;
    }
    fn child(self: *Space, parent: usize, index: usize) !usize {
        const pte = &self.tables[parent].entries[index];
        if (pte.* & 1 == 0) {
            if (self.used == self.tables.len) return error.OutOfTables;
            const next = self.used;
            self.used += 1;
            pte.* = @intFromPtr(&self.tables[next]) | 3;
            return next;
        }
        if (pte.* & 3 != 3) return error.MappingConflict;
        const address = pte.* & mask;
        const base = @intFromPtr(self.tables.ptr);
        if (address < base or (address - base) / 4096 >= self.used) return error.InvalidTable;
        return @intCast((address - base) / 4096);
    }
    fn mapFlags(self: *Space, virtual: u64, paddr: u64, flags: u64) !void {
        if ((virtual | paddr) & 4095 != 0 or virtual >> 48 != 0 or paddr & ~mask != 0) return error.InvalidAddress;
        var table: usize = 0;
        for ([_]u6{ 39, 30, 21 }) |shift| table = try self.child(table, @intCast((virtual >> shift) & 511));
        const pte = &self.tables[table].entries[@intCast((virtual >> 12) & 511)];
        if (pte.* != 0) return error.MappingConflict;
        pte.* = paddr | flags;
    }
    pub fn map(self: *Space, virtual: u64, paddr: u64, write_access: bool, executable: bool) !void {
        try self.mapFlags(virtual, paddr, 3 | (1 << 10) | (3 << 8) | (1 << 6) |
            (if (write_access) @as(u64, 0) else 1 << 7) | (1 << 53) | (if (executable) @as(u64, 0) else 1 << 54));
    }
    pub fn mapKernel(self: *Space, virtual: u64, paddr: u64) !void {
        // RAM framebuffers already reside in the supervisor identity block.
        if (virtual == paddr and virtual >= 0x40000000 and virtual < 0x80000000) return;
        try self.mapFlags(virtual, paddr, 3 | (1 << 10) | (1 << 2) | (1 << 53) | (1 << 54));
    }
    pub fn readable(self: *Space, address: u64, length: u64) bool {
        if (length > 4096 or address >> 48 != 0 or length > (1 << 48) - address) return false;
        if (length == 0) return true;
        var page = address & ~@as(u64, 4095);
        const last = (address + length - 1) & ~@as(u64, 4095);
        while (true) : (page += 4096) {
            var table: *const Table = &self.tables[0];
            for ([_]u6{ 39, 30, 21, 12 }) |shift| {
                const pte = table.entries[@intCast((page >> shift) & 511)];
                if (pte & 1 == 0) return false;
                if (shift == 12 or pte & 3 != 3) {
                    if (pte & (1 << 6) == 0) return false;
                    break;
                }
                table = @ptrFromInt(pte & mask);
            }
            if (page == last) return true;
        }
    }
    pub fn writable(self: *Space, address: u64, length: u64) bool {
        if (length > 4096 or address >> 48 != 0 or length > (1 << 48) - address) return false;
        if (length == 0) return true;
        var page = address & ~@as(u64, 4095);
        const last = (address + length - 1) & ~@as(u64, 4095);
        while (true) : (page += 4096) {
            var table: *const Table = &self.tables[0];
            for ([_]u6{ 39, 30, 21, 12 }) |shift| {
                const pte = table.entries[@intCast((page >> shift) & 511)];
                if (pte & 1 == 0) return false;
                if (shift == 12 or pte & 3 != 3) {
                    if (pte & (1 << 6) == 0 or pte & (1 << 7) != 0) return false;
                    break;
                }
                table = @ptrFromInt(pte & mask);
            }
            if (page == last) return true;
        }
    }
    pub const mapPage = map;
    /// Table storage remains owned by the address space until its final teardown.
    pub fn unmapPage(self: *Space, address: u64) !u64 {
        if (address & 4095 != 0 or address >= 1 << 38) return error.InvalidAddress;
        var table: *Table = &self.tables[0];
        for ([_]u6{ 39, 30, 21 }) |shift| {
            const pte = table.entries[@intCast((address >> shift) & 511)];
            if (pte & 3 != 3) return error.MissingMapping;
            table = @ptrFromInt(pte & mask);
        }
        const pte = &table.entries[@intCast((address >> 12) & 511)];
        if (pte.* & 3 != 3) return error.MissingMapping;
        const physical_address = pte.* & mask;
        pte.* = 0;
        return physical_address;
    }
    pub fn activate(self: *Space) void {
        const features = asm volatile ("mrs %[value], id_aa64mmfr0_el1"
            : [value] "=r" (-> u64),
        );
        const tcr: u64 = 16 | (1 << 8) | (1 << 10) | (3 << 12) | (1 << 23) | ((features & 0xf) << 32);
        asm volatile ("dsb ish; msr mair_el1, %[mair]; msr tcr_el1, %[tcr]; msr ttbr0_el1, %[root]; isb; tlbi vmalle1; dsb ish; isb"
            :
            : [mair] "r" (@as(u64, 0xff)),
              [tcr] "r" (tcr),
              [root] "r" (@intFromPtr(&self.tables[0])),
            : .{ .memory = true });
        const sctlr = asm volatile ("mrs %[value], sctlr_el1"
            : [value] "=r" (-> u64),
        );
        asm volatile ("msr sctlr_el1, %[value]; isb"
            :
            : [value] "r" (sctlr | 0x1005),
            : .{ .memory = true });
    }
};
pub fn initialize() void {
    asm volatile ("msr vbar_el1, %[vector]; isb"
        :
        : [vector] "r" (@intFromPtr(&arch_user_vector)),
        : .{ .memory = true });
}
pub fn initial(pc: u64, stack: u64, info: u64) Frame {
    var f: Frame = .{ .pc = pc, .sp = stack & ~@as(u64, 15) };
    f.regs[0] = info;
    return f;
}
pub fn decode(f: *const Frame) Call {
    return .{ .value = f.regs[8], .a = f.regs[0], .b = f.regs[1], .c = f.regs[2], .words = .{ f.regs[3], f.regs[4], f.regs[5], f.regs[6] } };
}
pub fn encode(f: *Frame, c: Call) void {
    f.regs[8] = c.value;
    f.regs[0] = c.a;
    f.regs[1] = c.b;
    f.regs[2] = c.c;
    @memcpy(f.regs[3..7], &c.words);
}
pub fn interrupt(f: *const Frame, kind: u64) ?@import("../irq_event.zig").Event {
    if (kind != 1) return null;
    if (f.status & 0xf != 0) @panic("kernel IRQ on user exception stack");
    return @import("irq.zig").claim();
}
pub fn exception(f: *Frame) ?@import("../../model/structures.zig").Fault {
    if (f.status & 0xf != 0) @panic("ARM kernel exception");
    const esr = asm volatile ("mrs %[v], esr_el1"
        : [v] "=r" (-> u64),
    );
    const ec = esr >> 26;
    if (ec == 0x15) return null;
    const far = asm volatile ("mrs %[v], far_el1"
        : [v] "=r" (-> u64),
    );
    if (ec == 0x20 or ec == 0x24) return .{ .vm = .{ .address = far, .status = esr, .instruction = ec == 0x20 } };
    return .{ .user_exception = .{ .number = ec, .code = esr & 0x1ffffff } };
}
pub const restore = arch_user_restore;

pub const faults = @import("fault.zig");
pub const elf_machine = std.elf.EM.AARCH64;
pub fn physical(address: u64) u64 {
    return address;
}

/// Distinguish the standard syscall entry from the private bootstrap services.
pub fn isNative(_: *const Frame) bool {
    const syndrome = asm volatile ("mrs %[v], esr_el1"
        : [v] "=r" (-> u64),
    );
    return syndrome & 0xffff == 0;
}
pub fn decodeNative(f: *const Frame) Call {
    return .{ .value = f.regs[7], .a = f.regs[0], .b = f.regs[1], .c = 0, .words = f.regs[2..6].* };
}
pub fn encodeNative(f: *Frame, badge: u64, tag: u64, words: [4]u64) void {
    f.regs[0] = badge;
    f.regs[1] = tag;
    @memcpy(f.regs[2..6], &words);
}
