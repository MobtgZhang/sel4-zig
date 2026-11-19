//! Native non-MCS syscall dispatch, following src/api/syscall.c.
//! Architecture trap entry must supply a validated current thread and CSpace.
const nums = @import("syscall_numbers.zig");
const s = @import("../model/structures.zig");
const Kernel = @import("../kernel/runtime.zig").Kernel;
const cspace = @import("../kernel/cspace.zig");
const endpoint = @import("../object/endpoint.zig");
const notification = @import("../object/notification.zig");
const reply = @import("../object/reply.zig");
pub const upstream_rel = "api/syscall.c";
pub const Error = error{ NoCurrentThread, FailedLookup, ExtraCapLookup, InvalidCapability, IllegalOperation, UnknownSyscall };

fn send(kernel: *Kernel, thread: *s.Thread, slot: *s.Slot, blocking: bool, call: bool) Error!void {
    switch (slot.cap) {
        .endpoint => |ep| try endpoint.send(&kernel.scheduler, thread, ep, blocking, call),
        .notification => |ntfn| {
            if (!ntfn.rights.write) return error.InvalidCapability;
            notification.signal(&kernel.scheduler, ntfn.object, ntfn.badge);
        },
        .reply => {
            if (call) return error.IllegalOperation;
            _ = reply.invokeSaved(&kernel.scheduler, thread, slot);
        },
        else => @import("invocation.zig").invoke(kernel, thread, slot, call),
    }
}
fn receive(kernel: *Kernel, thread: *s.Thread, cap: s.Capability, blocking: bool) Error!void {
    switch (cap) {
        .endpoint => |ep| try endpoint.receive(&kernel.scheduler, thread, ep, blocking),
        .notification => |ntfn| {
            if (!ntfn.rights.read) return error.InvalidCapability;
            try notification.receive(&kernel.scheduler, thread, ntfn.object, blocking);
        },
        else => return error.InvalidCapability,
    }
}

pub fn dispatch(kernel: *Kernel, number: i64, cptr: u64) Error!void {
    const thread = kernel.scheduler.current orelse return error.NoCurrentThread;
    if (!thread.isRunnable()) return error.NoCurrentThread;
    defer {
        _ = kernel.scheduler.schedule();
    }
    switch (number) {
        nums.seL4_SysYield => kernel.scheduler.yield(),
        nums.seL4_SysReply => {
            _ = reply.invoke(&kernel.scheduler, thread);
        },
        nums.seL4_SysDebugPutChar => if (kernel.debug_output) |output| {
            output(@truncate(cptr));
        } else return error.IllegalOperation,
        nums.seL4_SysSend, nums.seL4_SysNBSend, nums.seL4_SysCall => {
            const blocking = number != nums.seL4_SysNBSend;
            const slot = cspace.lookupSlot(thread.cspace, cptr) catch {
                if (blocking) return error.FailedLookup;
                return;
            };
            if (!slot.cap.isValid()) {
                if (blocking) return error.InvalidCapability;
                return;
            }
            // Extra-cap lookup faults precede both IPC transfer and object decoding.
            // NBSend still drops the failure without blocking or changing the endpoint.
            if (thread.has_ipc_buffer and thread.extra_cap_fault != null) {
                if (blocking) return error.ExtraCapLookup;
                return;
            }
            send(kernel, thread, slot, blocking, number == nums.seL4_SysCall) catch |err| {
                // NBSend drops a failed invocation without delivering a capability fault.
                if (blocking) return err;
            };
        },
        nums.seL4_SysRecv, nums.seL4_SysNBRecv, nums.seL4_SysReplyRecv => {
            if (number == nums.seL4_SysReplyRecv) _ = reply.invoke(&kernel.scheduler, thread);
            const slot = try cspace.lookupSlot(thread.cspace, cptr);
            try receive(kernel, thread, slot.cap, number != nums.seL4_SysNBRecv);
        },
        else => {
            thread.fault = .{ .unknown_syscall = number };
            return error.UnknownSyscall;
        },
    }
}
