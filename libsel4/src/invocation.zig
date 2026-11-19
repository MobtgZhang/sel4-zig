//! Common object bindings for the configured non-MCS invocation label set.
const sel4 = @import("sel4.zig");
const labels = @import("invocation_labels");

fn call(service: u64, label: u52, args: []const u64, caps: []const u64) u64 {
    for (args, 0..) |word, i| sel4.seL4_SetMR(i, word);
    for (caps, 0..) |cap, i| sel4.seL4_SetCap(i, cap);
    return sel4.seL4_Call(service, sel4.MessageInfo.init(label, @intCast(caps.len), @intCast(args.len))).label();
}

pub fn seL4_CNode_Copy(dest: u64, index: u64, depth: u8, source: u64, source_index: u64, source_depth: u8, rights: u64) u64 {
    return call(dest, labels.CNodeCopy, &.{ index, depth, source_index, source_depth, rights }, &.{source});
}
pub fn seL4_CNode_Mint(dest: u64, index: u64, depth: u8, source: u64, source_index: u64, source_depth: u8, rights: u64, data: u64) u64 {
    return call(dest, labels.CNodeMint, &.{ index, depth, source_index, source_depth, rights, data }, &.{source});
}
pub fn seL4_CNode_Move(dest: u64, index: u64, depth: u8, source: u64, source_index: u64, source_depth: u8) u64 {
    return call(dest, labels.CNodeMove, &.{ index, depth, source_index, source_depth }, &.{source});
}
pub fn seL4_CNode_Mutate(dest: u64, index: u64, depth: u8, source: u64, source_index: u64, source_depth: u8, data: u64) u64 {
    return call(dest, labels.CNodeMutate, &.{ index, depth, source_index, source_depth, data }, &.{source});
}
pub fn seL4_CNode_Rotate(dest: u64, index: u64, depth: u8, dest_data: u64, pivot: u64, pivot_index: u64, pivot_depth: u8, pivot_data: u64, source: u64, source_index: u64, source_depth: u8) u64 {
    return call(dest, labels.CNodeRotate, &.{ index, depth, dest_data, pivot_index, pivot_depth, pivot_data, source_index, source_depth }, &.{ pivot, source });
}
pub fn seL4_CNode_Revoke(root: u64, index: u64, depth: u8) u64 {
    return call(root, labels.CNodeRevoke, &.{ index, depth }, &.{});
}
pub fn seL4_CNode_Delete(root: u64, index: u64, depth: u8) u64 {
    return call(root, labels.CNodeDelete, &.{ index, depth }, &.{});
}
pub fn seL4_CNode_CancelBadgedSends(root: u64, index: u64, depth: u8) u64 {
    return call(root, labels.CNodeCancelBadgedSends, &.{ index, depth }, &.{});
}
pub fn seL4_CNode_SaveCaller(root: u64, index: u64, depth: u8) u64 {
    return call(root, labels.CNodeSaveCaller, &.{ index, depth }, &.{});
}
pub fn seL4_TCB_SetPriority(target: u64, authority: u64, priority: u64) u64 {
    return call(target, labels.TCBSetPriority, &.{priority}, &.{authority});
}
pub fn seL4_TCB_SetMCPriority(target: u64, authority: u64, priority: u64) u64 {
    return call(target, labels.TCBSetMCPriority, &.{priority}, &.{authority});
}
pub fn seL4_TCB_SetSchedParams(target: u64, authority: u64, mcp: u64, priority: u64) u64 {
    return call(target, labels.TCBSetSchedParams, &.{ mcp, priority }, &.{authority});
}
pub fn seL4_TCB_Suspend(target: u64) u64 {
    return call(target, labels.TCBSuspend, &.{}, &.{});
}
pub fn seL4_TCB_Resume(target: u64) u64 {
    return call(target, labels.TCBResume, &.{}, &.{});
}
pub fn seL4_TCB_SetAffinity(target: u64, cpu: u64) u64 {
    return call(target, labels.TCBSetAffinity, &.{cpu}, &.{});
}
pub fn seL4_TCB_BindNotification(target: u64, notification: u64) u64 {
    return call(target, labels.TCBBindNotification, &.{}, &.{notification});
}
pub fn seL4_TCB_UnbindNotification(target: u64) u64 {
    return call(target, labels.TCBUnbindNotification, &.{}, &.{});
}
pub fn seL4_Untyped_Retype(service: u64, kind: u64, size_bits: u64, root: u64, node_index: u64, node_depth: u64, node_offset: u64, count: u64) u64 {
    return call(service, labels.UntypedRetype, &.{ kind, size_bits, node_index, node_depth, node_offset, count }, &.{root});
}
pub fn seL4_IRQControl_Get(service: u64, irq: u64, root: u64, index: u64, depth: u8) u64 {
    return call(service, labels.IRQIssueIRQHandler, &.{ irq, index, depth }, &.{root});
}
pub fn seL4_IRQHandler_Ack(service: u64) u64 {
    return call(service, labels.IRQAckIRQ, &.{}, &.{});
}
pub fn seL4_IRQHandler_SetNotification(service: u64, notification: u64) u64 {
    return call(service, labels.IRQSetIRQHandler, &.{}, &.{notification});
}
pub fn seL4_IRQHandler_Clear(service: u64) u64 {
    return call(service, labels.IRQClearIRQHandler, &.{}, &.{});
}
