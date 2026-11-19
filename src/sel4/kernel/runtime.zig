//! Non-MCS kernel state protected by the shared SMP kernel lock.
const s = @import("../model/structures.zig");
const caps = @import("../model/capability.zig");
const cnode = @import("../object/cnode.zig");
const endpoint = @import("../object/endpoint.zig");
const notification = @import("../object/notification.zig");
const reply = @import("../object/reply.zig");
const irq = @import("../object/interrupt.zig");
const mutex = @import("mutex.zig");
pub const Scheduler = @import("thread.zig").Scheduler;

pub const Kernel = struct {
    scheduler: Scheduler,
    irqs: irq.IrqTable = .{},
    debug_output: ?*const fn (u8) void = null,

    pub fn init(idle: *s.Thread) Kernel {
        return .{ .scheduler = Scheduler.init(idle) };
    }
    pub fn cancelIpc(self: *Kernel, thread: *s.Thread) void {
        switch (thread.state) {
            .blocked_send, .blocked_receive => endpoint.cancel(&self.scheduler, thread),
            .blocked_notification => notification.cancel(&self.scheduler, thread),
            .blocked_mutex => mutex.cancelWait(&self.scheduler, thread),
            .blocked_reply => {
                if (thread.reply_owner) |server| reply.discard(server);
                if (thread.saved_reply_slot) |slot| {
                    thread.saved_reply_slot = null;
                    cnode.unlink(slot);
                }
                self.scheduler.block(thread, .inactive);
            },
            else => {},
        }
    }
    pub fn suspendThread(self: *Kernel, thread: *s.Thread) void {
        self.cancelIpc(thread);
        self.scheduler.block(thread, .inactive);
    }

    /// Delete all descendants before recycling an object's backing memory.
    pub fn revoke(self: *Kernel, slot: *s.Slot) void {
        while (slot.next) |child| {
            if (!cnode.isParentOf(slot, child)) break;
            self.delete(child);
        }
    }
    pub fn delete(self: *Kernel, slot: *s.Slot) void {
        if (!slot.cap.isValid()) return;
        if (cnode.isFinal(slot)) {
            switch (slot.cap) {
                .endpoint => |cap| endpoint.cancelAll(&self.scheduler, cap.object),
                .notification => |cap| {
                    self.irqs.clearNotification(cap.object);
                    notification.cancelAll(&self.scheduler, cap.object);
                },
                .tcb => |thread| {
                    self.suspendThread(thread);
                    thread.user_context_ready = false;
                    mutex.releaseAll(&self.scheduler, thread);
                    reply.discard(thread);
                    if (thread.bound_notification) |object| notification.unbind(object);
                    thread.cspace = .{ .null_cap = {} };
                },
                .cnode => |cap| {
                    // Detach the owner first to terminate a self-referencing CNode.
                    cnode.unlink(slot);
                    for (cap.slots) |*child| self.delete(child);
                    return;
                },
                .reply => |cap| {
                    if (cap.thread.saved_reply_slot == slot) cap.thread.saved_reply_slot = null;
                },
                .irq_handler => |number| self.irqs.release(number),
                else => {},
            }
        }
        cnode.unlink(slot);
    }
};
