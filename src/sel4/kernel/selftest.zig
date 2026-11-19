//! Allocation-free boot regression: capability lookup, scheduling, and Call/Reply.
//! This runs in kernel mode and does not stand in for a userspace integration test.
const s = @import("../model/structures.zig");
const Kernel = @import("runtime.zig").Kernel;
const syscall = @import("../api/syscall.zig");
const nums = @import("../api/syscall_numbers.zig");

pub fn run() !void {
    try @import("mutex.zig").selfTest();
    if (comptime @import("builtin").os.tag == .freestanding) {
        var lock: @import("../platform/sync.zig").SpinLock = .{};
        const flags = lock.lockIrqSave();
        if (lock.tryLock()) return error.SpinLockFailed;
        lock.unlockIrqRestore(flags);
        if (!lock.tryLock()) return error.SpinLockFailed;
        lock.unlock();
    }
    var idle: s.Thread = .{};
    var kernel = Kernel.init(&idle);
    var slots: [4]s.Slot = @splat(.{});
    var endpoint: s.Endpoint = .{};
    slots[1].cap = .{ .endpoint = .{ .object = &endpoint, .badge = 0x42 } };
    const root: s.Capability = .{ .cnode = try s.CNodeCap.init(&slots, 0, 62) };
    var client: s.Thread = .{ .state = .running, .cspace = root, .priority = 20 };
    var server: s.Thread = .{ .state = .running, .cspace = root, .priority = 10 };
    kernel.scheduler.current = &server;
    kernel.scheduler.enqueue(&client);
    try syscall.dispatch(&kernel, nums.seL4_SysRecv, 1);
    try syscall.dispatch(&kernel, nums.seL4_SysCall, 1);
    if (kernel.scheduler.current != &server or client.state != .blocked_reply or server.badge != 0x42) return error.CallFailed;
    server.message_info = s.MessageInfo.init(0, 0, 0, 1);
    server.message[0] = 0xcafe;
    try syscall.dispatch(&kernel, nums.seL4_SysReplyRecv, 1);
    if (kernel.scheduler.current != &client or client.message[0] != 0xcafe or server.state != .blocked_receive) return error.ReplyFailed;
}
