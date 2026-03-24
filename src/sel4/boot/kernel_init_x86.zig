//! 仅 x86_64 目标编译：IDT、#PF/#DE 探测。
const std = @import("std");
const handoff = @import("handoff.zig");
const idt_lite = @import("../baremetal/idt_lite.zig");
const serial_out = @import("../baremetal/serial_plat.zig");
const faults = @import("../api/faults.zig");

extern fn x86_lidt(desc: *const [10]u8) callconv(.c) void;
extern fn isr_divide_error() void;
extern fn isr_page_fault() void;

var idt_storage: [256]idt_lite.IdtEntry align(16) = undefined;

fn hang() noreturn {
    while (true) asm volatile ("hlt");
}

fn lidtRaw(limit: u16, base: u64) void {
    var blob: [10]u8 = undefined;
    std.mem.writeInt(u16, blob[0..2], limit, .little);
    std.mem.writeInt(u64, blob[2..10], base, .little);
    x86_lidt(&blob);
}

fn installDivideErrorHandler() void {
    const code_sel: u16 = 8;
    const handler = @intFromPtr(&isr_divide_error);
    idt_storage[0] = idt_lite.IdtEntry.initInterruptGate(code_sel, handler, 0);
}

fn installPageFaultHandler() void {
    const code_sel: u16 = 8;
    const handler = @intFromPtr(&isr_page_fault);
    idt_storage[14] = idt_lite.IdtEntry.initInterruptGate(code_sel, handler, 0);
}

fn installIdt() void {
    @memset(std.mem.asBytes(&idt_storage), 0);
    installDivideErrorHandler();
    installPageFaultHandler();
    const lim: u16 = @intCast(@sizeOf(@TypeOf(idt_storage)) - 1);
    lidtRaw(lim, @intFromPtr(&idt_storage));
}

fn provokePageFault() void {
    asm volatile (
        \\ movabs $0x400000, %%rax
        \\ movq (%%rax), %%rax
        ::: .{ .rax = true, .memory = true });
}

fn provokeDivideByZero() void {
    asm volatile (
        \\ movl $1, %%eax
        \\ xorl %%edx, %%edx
        \\ movl $0, %%ecx
        \\ divl %%ecx
        ::: .{ .eax = true, .ecx = true, .edx = true, .memory = true });
}

pub fn runX86Smoke(h: *const handoff.BootHandoff) noreturn {
    installIdt();
    serial_out.serialWriteSlice("IDT: vec 14 (#PF) + vec 0 (#DE)\r\n");
    if ((h.flags & 2) == 0) {
        serial_out.serialWriteSlice("provoking #PF (not UEFI handoff)...\r\n");
        provokePageFault();
        faults.reportUnexpectedReturn("#PF");
    } else {
        serial_out.serialWriteSlice("UEFI handoff: skip #PF probe\r\n");
    }
    serial_out.serialWriteSlice("IDT: provoking div0...\r\n");
    provokeDivideByZero();
    faults.reportUnexpectedReturn("#DE");
    hang();
}
