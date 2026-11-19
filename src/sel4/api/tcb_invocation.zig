//! Architecture-independent TCB controls. Register/VSpace controls need arch hooks.
const s = @import("../model/structures.zig");
const Kernel = @import("../kernel/runtime.zig").Kernel;
const invocation = @import("invocation.zig");
const Request = invocation.Request;
const Error = invocation.Error;
const labels = @import("invocation_labels.zig");
const tcb = @import("../object/tcb.zig");
const notification = @import("../object/notification.zig");

pub fn decode(kernel: *Kernel, request: *Request, target: *s.Thread, label: u52) Error!void {
    switch (label) {
        labels.TCBSuspend => kernel.suspendThread(target),
        labels.TCBResume => {
            // Dynamic TCB register/VSpace configuration is not implemented yet.
            // Reject it explicitly instead of scheduling a thread with no frame.
            if (!target.user_context_ready) return error.IllegalOperation;
            tcb.resumeThread(&kernel.scheduler, target);
        },
        labels.TCBSetPriority, labels.TCBSetMCPriority, labels.TCBSetSchedParams => {
            const combined = label == labels.TCBSetSchedParams;
            try request.require(if (combined) 2 else 1, 1);
            const authority = request.extra(0);
            if (authority != .tcb) return request.invalidCap(1);
            const limit = authority.tcb.max_controlled_priority;
            if (request.arg(0) > limit or (combined and request.arg(1) > limit)) return request.range(0, limit);
            // Validate both scheduling parameters before updating either field.
            if (label != labels.TCBSetPriority) target.max_controlled_priority = @intCast(request.arg(0));
            if (label != labels.TCBSetMCPriority) kernel.scheduler.setPriority(target, @intCast(request.arg(if (combined) 1 else 0)));
        },
        labels.TCBBindNotification => {
            try request.require(0, 1);
            const cap = request.extra(0);
            if (cap != .notification or !cap.notification.rights.read) return request.invalidCap(1);
            try notification.bind(cap.notification.object, target);
        },
        labels.TCBUnbindNotification => {
            const object = target.bound_notification orelse return error.IllegalOperation;
            notification.unbind(object);
        },
        labels.TCBSetAffinity => {
            try request.require(1, 0);
            const cpu = request.arg(0);
            if (cpu >= 64) return request.range(0, 63);
            const mask = @as(u64, 1) << @as(u6, @intCast(cpu));
            if (mask & kernel.scheduler.online_mask == 0) return request.invalidArgument(0);
            try kernel.scheduler.setAffinity(target, mask);
        },
        else => return error.IllegalOperation,
    }
}
