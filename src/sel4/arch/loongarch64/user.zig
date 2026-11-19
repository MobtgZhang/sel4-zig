//! LoongArch PLV3 contexts, 4 KiB mappings and software TLB refill.
const std = @import("std");
const Call = @import("../user_call.zig").Call;
pub const Table = extern struct { entries: [512]u64 = @splat(0) };
pub const Frame = extern struct {
    regs: [32]u64 = @splat(0),
    pc: u64 = 0,
    status: u64 = 7,
    fp: [32]u64 = @splat(0),
    fcsr: u64 = 0,
    fcc: u64 = 0,
};
comptime {
    std.debug.assert(@sizeOf(Frame) == 544);
}
extern fn arch_user_restore(*const Frame) callconv(.c) noreturn;
extern fn arch_user_vector() void;
extern fn arch_tlb_refill() void;
var kernel_stack: [128 * 1024]u8 align(16) = undefined;
pub const Space = struct {
    tables: []Table,
    used: usize = 1,
    pub fn init(tables: []Table) !Space {
        @memset(std.mem.sliceAsBytes(tables), 0);
        const self: Space = .{ .tables = tables };
        // Kernel RAM and devices remain in PLV0-only direct mapping windows.
        return self;
    }
    fn child(self: *Space, parent: usize, index: usize) !usize {
        const pte = &self.tables[parent].entries[index];
        if (pte.* == 0) {
            if (self.used == self.tables.len) return error.OutOfTables;
            const next = self.used;
            self.used += 1;
            pte.* = physical(@intFromPtr(&self.tables[next]));
            return next;
        }
        const address = pte.* | 0x9000000000000000;
        const base = @intFromPtr(self.tables.ptr);
        if (address < base or (address - base) / 4096 >= self.used) return error.InvalidTable;
        return @intCast((address - base) / 4096);
    }
    fn mapFlags(self: *Space, virtual: u64, paddr: u64, flags: u64) !void {
        if ((virtual | paddr) & 4095 != 0 or virtual >= 1 << 38) return error.InvalidAddress;
        const l1 = try self.child(0, @intCast((virtual >> 30) & 511));
        const l0 = try self.child(l1, @intCast((virtual >> 21) & 511));
        const pte = &self.tables[l0].entries[@intCast((virtual >> 12) & 511)];
        if (pte.* != 0) return error.MappingConflict;
        pte.* = paddr | flags;
    }
    pub fn map(self: *Space, virtual: u64, paddr: u64, write_access: bool, executable: bool) !void {
        try self.mapFlags(virtual, paddr, 0x1d | (if (write_access) @as(u64, 2) else 0) | (if (executable) @as(u64, 0) else 1 << 62));
    }
    pub fn mapKernel(self: *Space, virtual: u64, paddr: u64) !void {
        _ = self;
        _ = virtual;
        _ = paddr; // PLV0 direct windows cover device apertures.
    }
    pub fn readable(self: *Space, address: u64, length: u64) bool {
        if (length > 4096 or address >= 1 << 38 or length > (1 << 38) - address) return false;
        if (length == 0) return true;
        var page = address & ~@as(u64, 4095);
        const last = (address + length - 1) & ~@as(u64, 4095);
        while (true) : (page += 4096) {
            var table: *const Table = &self.tables[0];
            for ([_]u6{ 30, 21 }) |shift| {
                const entry = table.entries[@intCast((page >> shift) & 511)];
                if (entry == 0) return false;
                table = @ptrFromInt(entry | 0x9000000000000000);
            }
            const leaf = table.entries[@intCast((page >> 12) & 511)];
            if (leaf & 0xd != 0xd or leaf & (1 << 61) != 0) return false;
            if (page == last) return true;
        }
    }
    pub fn writable(self: *Space, address: u64, length: u64) bool {
        if (length > 4096 or address >= 1 << 38 or length > (1 << 38) - address) return false;
        if (length == 0) return true;
        var page = address & ~@as(u64, 4095);
        const last = (address + length - 1) & ~@as(u64, 4095);
        while (true) : (page += 4096) {
            var table: *const Table = &self.tables[0];
            for ([_]u6{ 30, 21 }) |shift| {
                const entry = table.entries[@intCast((page >> shift) & 511)];
                if (entry == 0) return false;
                table = @ptrFromInt(entry | 0x9000000000000000);
            }
            const leaf = table.entries[@intCast((page >> 12) & 511)];
            if (leaf & 0xf != 0xf or leaf & (1 << 61) != 0) return false;
            if (page == last) return true;
        }
    }
    pub const mapPage = map;
    /// Table storage remains owned by the address space until its final teardown.
    pub fn unmapPage(self: *Space, address: u64) !u64 {
        if (address & 4095 != 0 or address >= 1 << 38) return error.InvalidAddress;
        var table: *Table = &self.tables[0];
        for ([_]u6{ 30, 21 }) |shift| {
            const pte = table.entries[@intCast((address >> shift) & 511)];
            if (pte == 0) return error.MissingMapping;
            table = @ptrFromInt(pte | 0x9000000000000000);
        }
        const pte = &table.entries[@intCast((address >> 12) & 511)];
        if (pte.* & 1 == 0) return error.MissingMapping;
        const physical_address = pte.* & 0x0000fffffffff000;
        pte.* = 0;
        return physical_address;
    }
    pub fn activate(self: *Space) void {
        const root = physical(@intFromPtr(&self.tables[0]));
        // TLB refill state is per CPU, including workers entering this space.
        const refill = physical(@intFromPtr(&arch_tlb_refill));
        asm volatile ("dbar 0; csrwr %[refill], 0x88; csrwr %[root], 0x19; invtlb 0x0, $zero, $zero"
            :
            : [root] "r" (root),
              [refill] "r" (refill),
            : .{ .memory = true });
    }
};
pub fn initialize() void {
    const cpu = @import("../../kernel/smp_dispatch.zig").index();
    const stack = if (cpu == @import("../../platform/runtime.zig").topology.boot_index)
        @intFromPtr(&kernel_stack) + kernel_stack.len
    else
        @import("../../platform/smp.zig").secondary_boot_stacks[cpu];
    const vector = @intFromPtr(&arch_user_vector);
    const refill = physical(@intFromPtr(&arch_tlb_refill));
    asm volatile ("csrwr %[vector], 0xc; csrwr %[refill], 0x88; csrwr $zero, 0x4; csrwr $zero, 0x18; csrwr %[stack], 0x31"
        :
        : [vector] "r" (vector),
          [refill] "r" (refill),
          [stack] "r" (stack),
        : .{ .memory = true });
}
pub fn initial(pc: u64, stack: u64, info: u64) Frame {
    var frame: Frame = .{ .pc = pc };
    frame.regs[3] = stack & ~@as(u64, 15);
    frame.regs[4] = info;
    return frame;
}
pub fn decode(f: *const Frame) Call {
    return .{ .value = f.regs[11], .a = f.regs[4], .b = f.regs[5], .c = f.regs[6], .words = .{ f.regs[7], f.regs[8], f.regs[9], f.regs[10] } };
}
pub fn encode(f: *Frame, c: Call) void {
    f.regs[11] = c.value;
    f.regs[4] = c.a;
    f.regs[5] = c.b;
    f.regs[6] = c.c;
    @memcpy(f.regs[7..11], &c.words);
}
pub fn interrupt(f: *const Frame, _: u64) ?@import("../irq_event.zig").Event {
    const estat = asm volatile ("csrrd %[v], 0x5"
        : [v] "=r" (-> u64),
    );
    if ((estat >> 16) & 0x3f != 0) return null;
    if (f.status & 3 != 3) @panic("kernel IRQ on user exception stack");
    return @import("irq.zig").claim(estat);
}
pub fn exception(f: *Frame) ?@import("../../model/structures.zig").Fault {
    if (f.status & 3 != 3) @panic("LoongArch kernel exception");
    const estat = asm volatile ("csrrd %[v], 0x5"
        : [v] "=r" (-> u64),
    );
    const code = (estat >> 16) & 0x3f;
    if (code == 11) {
        f.pc += 4;
        return null;
    }
    const address = asm volatile ("csrrd %[v], 0x7"
        : [v] "=r" (-> u64),
    );
    if (code >= 1 and code <= 7) return .{ .vm = .{ .address = address, .status = estat, .instruction = code == 3 or code == 6 } };
    return .{ .user_exception = .{ .number = code, .code = estat } };
}
pub const restore = arch_user_restore;
pub const faults = @import("fault.zig");
pub const elf_machine = std.elf.EM.LOONGARCH;
pub fn physical(address: u64) u64 {
    return address & 0x0000ffffffffffff;
}

/// Distinguish the standard syscall entry from the private bootstrap services.
pub fn isNative(f: *const Frame) bool {
    return @as(i64, @bitCast(f.regs[11])) < 0;
}
pub fn decodeNative(f: *const Frame) Call {
    return .{ .value = f.regs[11], .a = f.regs[4], .b = f.regs[5], .c = 0, .words = f.regs[6..10].* };
}
pub fn encodeNative(f: *Frame, badge: u64, tag: u64, words: [4]u64) void {
    f.regs[4] = badge;
    f.regs[5] = tag;
    @memcpy(f.regs[6..10], &words);
}
