//! CPU primitives used by architecture-neutral kernel code.
pub const uart = @import("serial_com1.zig");
pub const interrupts = @import("interrupts.zig");
pub const smp = @import("smp.zig");
pub const display = @import("vga.zig");
pub const keyboard = @import("ps2.zig");
pub fn halt() noreturn {
    while (true) asm volatile ("hlt");
}
pub fn relax() void {
    asm volatile ("pause");
}
pub fn currentHardwareId() u64 {
    return asm volatile ("cpuid"
        : [id] "={ebx}" (-> u32),
        : [leaf] "{eax}" (@as(u32, 1)),
        : .{ .eax = true, .ecx = true, .edx = true }) >> 24;
}

/// Order DMA descriptor publication and device completion reads.
pub fn dmaBarrier() void {
    asm volatile ("mfence" ::: .{ .memory = true });
}

pub const firmware = @import("uefi.zig");

pub const virtio = @import("virtio.zig");

/// Translate a physical RAM address into the permanent kernel window.
pub fn directAddress(address: u64) usize {
    return @intCast(address);
}

/// Framebuffers use the uncached device window when the CPU provides one.
pub fn framebufferAddress(address: u64) usize {
    return @intCast(address);
}

pub const timer = @import("timer.zig");

pub const tlb = @import("tlb.zig");

pub const irq = @import("irq.zig");

pub const clock = @import("clock.zig");
