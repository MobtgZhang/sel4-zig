//! Early x86 exception gates; normal boot does not intentionally raise faults.
const std = @import("std");
const IdtEntry = @import("idt.zig").IdtEntry;
extern fn x86_lidt(desc: *const [10]u8) callconv(.c) void;
extern fn isr_divide_error() void;
extern fn isr_page_fault() void;
var idt: [256]IdtEntry align(16) = undefined;

pub fn install() void {
    @memset(std.mem.asBytes(&idt), 0);
    // UEFI can leave a different code selector from the Multiboot GDT.
    const selector = asm volatile ("mov %%cs, %[out]"
        : [out] "=r" (-> u16),
    );
    idt[0] = IdtEntry.initInterruptGate(selector, @intFromPtr(&isr_divide_error), 0);
    idt[14] = IdtEntry.initInterruptGate(selector, @intFromPtr(&isr_page_fault), 0);
    var descriptor: [10]u8 = undefined;
    std.mem.writeInt(u16, descriptor[0..2], @sizeOf(@TypeOf(idt)) - 1, .little);
    std.mem.writeInt(u64, descriptor[2..10], @intFromPtr(&idt), .little);
    x86_lidt(&descriptor);
}
