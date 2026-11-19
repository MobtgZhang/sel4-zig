//! CPU primitives used by architecture-neutral kernel code.
pub const uart = @import("uart.zig");
pub const interrupts = @import("interrupts.zig");
pub const smp = @import("smp.zig");
pub const display = @import("../../drivers/ramfb.zig");
pub const keyboard = @import("../../drivers/virtio_input.zig");
pub const fw_cfg_base: usize = 0x10100000;
pub fn halt() noreturn {
    while (true) asm volatile ("wfi");
}
pub fn relax() void {
    asm volatile ("nop");
}
pub fn currentHardwareId() u64 {
    return asm volatile ("mv %[id], tp"
        : [id] "=r" (-> u64),
    );
}

pub const user = @import("user.zig");

/// Order DMA descriptor publication and device completion reads.
pub fn dmaBarrier() void {
    asm volatile ("fence iorw, iorw" ::: .{ .memory = true });
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
