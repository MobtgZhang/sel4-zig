//! Sv39 user address spaces and supervisor exception context.
const std = @import("std");
const Call = @import("../user_call.zig").Call;
pub const Table = extern struct { entries: [512]u64 = @splat(0) };
pub const Frame = extern struct {
    regs: [32]u64 = @splat(0),
    pc: u64 = 0,
    status: u64 = 0x46020,
    fp: [32]u64 = @splat(0),
    fcsr: u64 = 0,
    padding: u64 = 0,
};
comptime {
    std.debug.assert(@sizeOf(Frame) == 544);
}
extern fn arch_user_restore(*const Frame) callconv(.c) noreturn;
extern fn arch_user_vector() void;
var kernel_stack: [128 * 1024]u8 align(16) = undefined;
pub const Space = struct {
    tables: []Table,
    used: usize = 1,
    pub fn init(tables: []Table) !Space {
        @memset(std.mem.sliceAsBytes(tables), 0);
        var self: Space = .{ .tables = tables };
        // Supervisor-only 1 GiB mapping covers kernel, boot records and initrd.
        self.tables[0].entries[2] = (0x80000000 >> 2) | 0xcf;
        try self.mapKernel(0x10000000, 0x10000000);
        for (1..33) |i| try self.mapKernel(0x10000000 + i * 4096, 0x10000000 + i * 4096);
        // Each supervisor PLIC context needs its own threshold and claim page.
        try self.mapKernel(0x0c000000, 0x0c000000);
        for (0..4) |i| try self.mapKernel(0x0c002000 + i * 4096, 0x0c002000 + i * 4096);
        const topology = &@import("../../platform/runtime.zig").topology;
        for (topology.cpus[0..topology.count]) |cpu| {
            if (cpu.hardware_id >= 64) return error.UnsupportedPlicContext;
            const address = 0x0c200000 + (cpu.hardware_id * 2 + 1) * 4096;
            try self.mapKernel(address, address);
        }
        return self;
    }
    fn child(self: *Space, parent: usize, index: usize) !usize {
        const pte = &self.tables[parent].entries[index];
        if (pte.* & 1 == 0) {
            if (self.used == self.tables.len) return error.OutOfTables;
            const next = self.used;
            self.used += 1;
            pte.* = (@intFromPtr(&self.tables[next]) >> 2) | 1;
            return next;
        }
        if (pte.* & 0xe != 0) return error.MappingConflict;
        const address = (pte.* >> 10) << 12;
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
        pte.* = (paddr >> 2) | flags;
    }
    pub fn map(self: *Space, virtual: u64, paddr: u64, write_access: bool, executable: bool) !void {
        try self.mapFlags(virtual, paddr, 0x53 | (if (write_access) @as(u64, 0x84) else 0) | (if (executable) @as(u64, 8) else 0));
    }
    pub fn mapKernel(self: *Space, virtual: u64, paddr: u64) !void {
        // RAM framebuffers already reside in the supervisor identity block.
        if (virtual == paddr and virtual >= 0x80000000 and virtual < 0xc0000000) return;
        try self.mapFlags(virtual, paddr, 0xc7);
    }
    pub fn readable(self: *Space, address: u64, length: u64) bool {
        if (length > 4096 or address >= 1 << 38 or length > (1 << 38) - address) return false;
        if (length == 0) return true;
        var page = address & ~@as(u64, 4095);
        const last = (address + length - 1) & ~@as(u64, 4095);
        while (true) : (page += 4096) {
            var table: *const Table = &self.tables[0];
            var level: u6 = 30;
            while (true) {
                const pte = table.entries[@intCast((page >> level) & 511)];
                if (pte & 1 == 0) return false;
                if (pte & 0xe != 0) {
                    if (pte & 0x12 != 0x12) return false;
                    break;
                }
                if (level == 12) return false;
                table = @ptrFromInt((pte >> 10) << 12);
                level -= 9;
            }
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
            var level: u6 = 30;
            while (true) {
                const pte = table.entries[@intCast((page >> level) & 511)];
                if (pte & 1 == 0) return false;
                if (pte & 0xe != 0) {
                    if (pte & 0x16 != 0x16) return false;
                    break;
                }
                if (level == 12) return false;
                table = @ptrFromInt((pte >> 10) << 12);
                level -= 9;
            }
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
            if (pte & 0xf != 1) return error.MissingMapping;
            table = @ptrFromInt((pte >> 10) << 12);
        }
        const pte = &table.entries[@intCast((address >> 12) & 511)];
        if (pte.* & 1 == 0) return error.MissingMapping;
        const physical_address = (pte.* >> 10) << 12;
        pte.* = 0;
        return physical_address;
    }
    pub fn activate(self: *Space) void {
        const satp = (@as(u64, 8) << 60) | (@intFromPtr(&self.tables[0]) >> 12);
        asm volatile ("csrw satp, %[value]; sfence.vma"
            :
            : [value] "r" (satp),
            : .{ .memory = true });
    }
};
pub fn initialize() void {
    const cpu = @import("../../kernel/smp_dispatch.zig").index();
    const top = if (cpu == @import("../../platform/runtime.zig").topology.boot_index)
        @intFromPtr(&kernel_stack) + kernel_stack.len
    else
        @import("../../platform/smp.zig").secondary_boot_stacks[cpu];
    const context: *[2]u64 = @ptrFromInt(top - 16);
    context.* = .{ top - 16, @import("backend.zig").currentHardwareId() };
    asm volatile ("csrw stvec, %[vector]; csrw sscratch, %[stack]"
        :
        : [vector] "r" (@intFromPtr(&arch_user_vector)),
          [stack] "r" (@intFromPtr(context)),
        : .{ .memory = true });
}
pub fn initial(pc: u64, stack: u64, info: u64) Frame {
    var frame: Frame = .{ .pc = pc };
    frame.regs[2] = stack & ~@as(u64, 15);
    frame.regs[10] = info;
    return frame;
}
pub fn decode(f: *const Frame) Call {
    return .{ .value = f.regs[17], .a = f.regs[10], .b = f.regs[11], .c = f.regs[12], .words = .{ f.regs[13], f.regs[14], f.regs[15], f.regs[16] } };
}
pub fn encode(f: *Frame, c: Call) void {
    f.regs[17] = c.value;
    f.regs[10] = c.a;
    f.regs[11] = c.b;
    f.regs[12] = c.c;
    @memcpy(f.regs[13..17], &c.words);
}
pub fn interrupt(f: *const Frame, _: u64) ?@import("../irq_event.zig").Event {
    const cause = asm volatile ("csrr %[v], scause"
        : [v] "=r" (-> u64),
    );
    if (cause >> 63 == 0) return null;
    if (f.status & 0x100 != 0) @panic("kernel IRQ on user exception stack");
    return @import("irq.zig").claim(cause);
}
pub fn exception(f: *Frame) ?@import("../../model/structures.zig").Fault {
    if (f.status & 0x100 != 0) @panic("RISC-V kernel exception");
    const cause = asm volatile ("csrr %[v], scause"
        : [v] "=r" (-> u64),
    );
    if (cause == 8) {
        f.pc += 4;
        return null;
    }
    const address = asm volatile ("csrr %[v], stval"
        : [v] "=r" (-> u64),
    );
    if (cause == 1 or cause == 5 or cause == 7 or cause == 12 or cause == 13 or cause == 15)
        return .{ .vm = .{ .address = address, .status = cause, .instruction = cause == 1 or cause == 12 } };
    return .{ .user_exception = .{ .number = cause, .code = address } };
}
pub const restore = arch_user_restore;

pub const faults = @import("fault.zig");
pub const elf_machine = std.elf.EM.RISCV;
pub fn physical(address: u64) u64 {
    return address;
}

/// Distinguish the standard syscall entry from the private bootstrap services.
pub fn isNative(f: *const Frame) bool {
    return @as(i64, @bitCast(f.regs[17])) < 0;
}
pub fn decodeNative(f: *const Frame) Call {
    return .{ .value = f.regs[17], .a = f.regs[10], .b = f.regs[11], .c = 0, .words = f.regs[12..16].* };
}
pub fn encodeNative(f: *Frame, badge: u64, tag: u64, words: [4]u64) void {
    f.regs[10] = badge;
    f.regs[11] = tag;
    @memcpy(f.regs[12..16], &words);
}
