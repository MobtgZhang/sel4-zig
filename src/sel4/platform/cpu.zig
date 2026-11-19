//! Hardware IDs and CPU lifecycle are separate from logical scheduler indices.
//! Discovered CPUs stay offline until their architecture startup acknowledges them.
const std = @import("std");
const handoff = @import("../boot/handoff.zig");
pub const State = enum(u8) { offline, starting, online, failed };
pub const Cpu = struct { hardware_id: u64 = 0, state: State = .offline };
pub const Topology = struct {
    cpus: [64]Cpu = @splat(.{}),
    count: usize = 0,
    boot_index: usize = 0,
    pub fn init(h: *const handoff.BootHandoff, boot_id: u64) !Topology {
        if (h.cpu_count > h.cpu_ids.len) return error.InvalidTopology;
        var result: Topology = .{};
        var found_boot = false;
        for (h.cpu_ids[0..h.cpu_count]) |id| {
            for (result.cpus[0..result.count]) |previous| if (previous.hardware_id == id) return error.DuplicateCpu;
            result.cpus[result.count] = .{ .hardware_id = id };
            if (id == boot_id) {
                result.boot_index = result.count;
                found_boot = true;
            }
            result.count += 1;
        }
        if (!found_boot) {
            if (result.count == result.cpus.len) return error.InvalidTopology;
            result.boot_index = result.count;
            result.cpus[result.count] = .{ .hardware_id = boot_id };
            result.count += 1;
        }
        result.cpus[result.boot_index].state = .online;
        return result;
    }
    pub fn onlineCount(self: *const Topology) usize {
        var count: usize = 0;
        for (self.cpus[0..self.count]) |*cpu| if (@atomicLoad(State, &cpu.state, .acquire) == .online) {
            count += 1;
        };
        return count;
    }
    pub fn beginStart(self: *Topology, index: usize) !void {
        if (index >= self.count or @cmpxchgStrong(State, &self.cpus[index].state, .offline, .starting, .acq_rel, .acquire) != null) return error.InvalidCpuState;
    }
    pub fn acknowledge(self: *Topology, index: usize, hardware_id: u64) !void {
        if (index >= self.count or self.cpus[index].hardware_id != hardware_id or
            @cmpxchgStrong(State, &self.cpus[index].state, .starting, .online, .release, .monotonic) != null) return error.InvalidCpuState;
    }
};
pub const currentHardwareId = @import("../arch/mod.zig").currentHardwareId;
test "topology never schedules a discovered but unacknowledged CPU" {
    var h: handoff.BootHandoff = .{};
    try handoff.addCpu(&h, 7);
    try handoff.addCpu(&h, 42);
    var topology = try Topology.init(&h, 42);
    try std.testing.expectEqual(@as(usize, 1), topology.onlineCount());
    try topology.beginStart(0);
    try std.testing.expectEqual(@as(usize, 1), topology.onlineCount());
    try std.testing.expectError(error.InvalidCpuState, topology.acknowledge(0, 8));
    try topology.acknowledge(0, 7);
    try std.testing.expectEqual(@as(usize, 2), topology.onlineCount());
    try std.testing.expectError(error.InvalidCpuState, topology.beginStart(0));
}
