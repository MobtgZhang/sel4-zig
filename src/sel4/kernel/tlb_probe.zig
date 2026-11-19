//! Real remote translation regression: warm page A, remap to B, invalidate, read B.
const runtime = @import("../platform/runtime.zig");
const smp = @import("../platform/smp.zig");
const shootdown = @import("../platform/tlb_shootdown.zig");
const arch = @import("../arch/mod.zig");
var lock: @import("../platform/sync.zig").SpinLock = .{};
var poisoned = false;

pub fn run(comptime Space: type, space: *Space, address: u64) !void {
    if (!lock.tryLock()) return error.ProbeBusy;
    defer lock.unlock();
    if (poisoned) return error.ProbePoisoned;
    errdefer poisoned = true;
    const Request = struct {
        space: *Space,
        address: u64,
        expected: u64,
        install: bool = true,
        failed: u32 = 0,
        fn read(argument: usize) void {
            const self: *@This() = @ptrFromInt(argument);
            if (self.install) self.space.activate();
            if (arch.backend.tlb.readUser(self.address) != self.expected)
                @atomicStore(u32, &self.failed, 1, .release);
        }
        fn all(self: *@This()) !void {
            for (runtime.topology.cpus[0..runtime.topology.count], 0..) |cpu, i| {
                if (cpu.state == .online and i != runtime.topology.boot_index)
                    try smp.submit(i, read, @intFromPtr(self));
            }
            for (runtime.topology.cpus[0..runtime.topology.count], 0..) |cpu, i| {
                if (cpu.state == .online and i != runtime.topology.boot_index) try smp.wait(i);
            }
            if (@atomicLoad(u32, &self.failed, .acquire) != 0) return error.StaleRemoteTranslation;
        }
    };
    const first = try runtime.pages.allocate();
    const second = runtime.pages.allocate() catch |err| {
        try runtime.pages.release(first);
        return err;
    };
    // On any failure retain both pages: a CPU might still have a usable translation.
    @as(*u64, @ptrCast(first.bytes().ptr)).* = 0x1122334455667788;
    @as(*u64, @ptrCast(second.bytes().ptr)).* = 0x8877665544332211;
    try space.mapPage(address, first.address, true, false);
    try shootdown.invalidateAll();
    const State = struct {
        var request: Request = undefined;
    };
    const request = &State.request;
    request.* = .{ .space = space, .address = address, .expected = 0x1122334455667788 };
    try request.all();
    _ = try space.unmapPage(address);
    try space.mapPage(address, second.address, true, false);
    try shootdown.invalidateAll();
    request.expected = 0x8877665544332211;
    request.install = false;
    try request.all();
    _ = try space.unmapPage(address);
    try shootdown.invalidateAll();
    @memset(first.bytes(), 0);
    @memset(second.bytes(), 0);
    try runtime.pages.release(first);
    try runtime.pages.release(second);
}
