//! Thread control operations for the native non-MCS core.
pub const upstream_rel = "object/tcb.c";
pub const upstream_arch_rel = "arch/x86/object/tcb.c";
const s = @import("../model/structures.zig");
const Scheduler = @import("../kernel/thread.zig").Scheduler;
pub const Thread = s.Thread;

pub fn setPriority(scheduler: *Scheduler, authority: *const Thread, target: *Thread, priority: u8) error{RangeError}!void {
    if (priority > authority.max_controlled_priority) return error.RangeError;
    scheduler.setPriority(target, priority);
}
pub fn setMcp(authority: *const Thread, target: *Thread, mcp: u8) error{RangeError}!void {
    if (mcp > authority.max_controlled_priority) return error.RangeError;
    target.max_controlled_priority = mcp;
}
pub fn resumeThread(scheduler: *Scheduler, target: *Thread) void {
    if (target.state != .inactive) return;
    target.state = .restart;
    scheduler.enqueue(target);
}
