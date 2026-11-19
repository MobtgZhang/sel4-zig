//! CPU primitives used by architecture-neutral kernel code.
pub const uart = @import("uart.zig");
pub const interrupts = @import("interrupts.zig");
pub const smp = @import("smp.zig");
pub const display = @import("../../drivers/ramfb.zig");
pub const keyboard = @import("../../drivers/virtio_input.zig");
pub const fw_cfg_base: usize = 0x09020000;
pub fn halt() noreturn {
    while (true) asm volatile ("wfe");
}
pub fn relax() void {
    asm volatile ("yield");
}
pub fn currentHardwareId() u64 {
    return asm volatile ("mrs %[id], mpidr_el1"
        : [id] "=r" (-> u64),
    ) & 0xff00ffffff;
}

pub const user = @import("user.zig");

/// Order DMA descriptor publication and device completion reads.
pub fn dmaBarrier() void {
    asm volatile ("dmb sy" ::: .{ .memory = true });
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
