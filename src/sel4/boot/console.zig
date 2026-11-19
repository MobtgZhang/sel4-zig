//! Recovery console with direct access to bounded kernel diagnostics.
const shell = @import("terminal");
const serial = @import("../platform/console.zig");
const handoff = @import("handoff.zig");
const selftest = @import("../kernel/selftest.zig");

pub fn fillInfo(info: *shell.abi.BootInfo, h: *const handoff.BootHandoff) void {
    info.* = .{};
    info.region_count = @min(h.region_count, info.regions.len);
    for (h.regions[0..info.region_count], 0..) |region, i| info.regions[i] = .{ .start = region.start, .end = region.end };
}
fn write(_: ?*anyopaque, bytes: []const u8) void {
    serial.serialWriteSlice(bytes);
}
fn read(_: ?*anyopaque) u8 {
    return serial.readBlocking();
}
fn check(_: ?*anyopaque) bool {
    selftest.run() catch return false;
    return true;
}
fn smp(_: ?*anyopaque) usize {
    @import("../platform/smp.zig").selfTest() catch return 0;
    return @import("../platform/runtime.zig").topology.onlineCount();
}
fn probe(_: ?*anyopaque) bool {
    return false;
}
fn system(_: ?*anyopaque, command: u64, argument: []const u8) bool {
    return @import("../fs/service.zig").run(command, argument);
}
pub fn run(h: *const handoff.BootHandoff) noreturn {
    var info: shell.abi.BootInfo = .{};
    fillInfo(&info, h);
    const console: shell.Console = .{
        .write_fn = write,
        .system_fn = system,
        .read_fn = read,
        .selftest_fn = check,
        .smp_fn = smp,
        .ipc_fn = check,
        .probe_fn = probe,
        .arch = @tagName(@import("builtin").cpu.arch),
        .mode = "kernel recovery console; normal mode runs isolated user tasks",
        .info = &info,
    };
    console.run();
}
