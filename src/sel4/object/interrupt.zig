//! IRQ handler state and notification delivery, independent of an IRQ controller.
pub const upstream_rel = "object/interrupt.c";
pub const upstream_arch_rel = "arch/x86/object/interrupt.c";
const s = @import("../model/structures.zig");
const notification = @import("notification.zig");
const Scheduler = @import("../kernel/thread.zig").Scheduler;
pub const Controller = struct {
    context: ?*anyopaque,
    /// Exclude controller holes and kernel-owned timer/IPI sources.
    valid: ?*const fn (u16) bool = null,
    mask: *const fn (?*anyopaque, u16, bool) void,
    acknowledge: *const fn (?*anyopaque, u16) void,
};
pub const IrqTable = struct {
    const Entry = struct { issued: bool = false, enabled: bool = false, signal: ?s.NotificationCap = null };
    entries: [256]Entry = @splat(.{}),
    controller: ?Controller = null,
    pub fn issue(self: *IrqTable, irq: u16) error{ RangeError, RevokeFirst }!void {
        if (irq >= self.entries.len) return error.RangeError;
        if (self.entries[irq].issued) return error.RevokeFirst;
        self.entries[irq] = .{ .issued = true, .enabled = true };
        if (self.controller) |c| c.mask(c.context, irq, false);
    }
    pub fn setNotification(self: *IrqTable, irq: u16, cap: s.NotificationCap) error{InvalidCapability}!void {
        if (irq >= self.entries.len or !self.entries[irq].issued or !cap.rights.write) return error.InvalidCapability;
        self.entries[irq].signal = cap;
    }
    pub fn handle(self: *IrqTable, scheduler: *Scheduler, irq: u16) error{InvalidCapability}!void {
        if (irq >= self.entries.len or !self.entries[irq].issued) return error.InvalidCapability;
        const entry = &self.entries[irq];
        if (entry.enabled) {
            entry.enabled = false;
            if (self.controller) |c| c.mask(c.context, irq, true);
            if (entry.signal) |cap| notification.signal(scheduler, cap.object, cap.badge);
        }
        if (self.controller) |c| c.acknowledge(c.context, irq);
    }
    pub fn ack(self: *IrqTable, irq: u16) error{InvalidCapability}!void {
        if (irq >= self.entries.len or !self.entries[irq].issued) return error.InvalidCapability;
        self.entries[irq].enabled = true;
        if (self.controller) |c| c.mask(c.context, irq, false);
    }
    pub fn clearNotification(self: *IrqTable, object: *s.Notification) void {
        for (&self.entries) |*entry| {
            if (entry.signal) |cap| if (cap.object == object) {
                entry.signal = null;
            };
        }
    }
    pub fn release(self: *IrqTable, irq: u16) void {
        if (irq >= self.entries.len) return;
        if (self.controller) |c| c.mask(c.context, irq, true);
        self.entries[irq] = .{};
    }
};
