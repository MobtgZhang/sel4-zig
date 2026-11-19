//! Initial task authority and placement, shared by every architecture runtime.
//! This bootstrap layout is project-specific; it is not upstream seL4 BootInfo.
const std = @import("std");
const s = @import("../model/structures.zig");
const abi = @import("terminal").abi;

/// Values match BootInfo.role and the fixed initial-task array in each runtime.
pub const Role = enum { terminal, echo, filesystem, probe };
pub const Slots = [16]s.Slot;

pub const Objects = struct {
    echo: *s.Endpoint,
    filesystem: *s.Endpoint,
    fault: *s.Endpoint,
    irq: *s.Notification,
    untyped_memory: []align(16) u8,
};

pub fn initialize(slots: *Slots, thread: *s.Thread, role: Role, objects: Objects) !void {
    const root: s.Capability = .{ .cnode = try s.CNodeCap.init(slots, 0, 60) };
    thread.cspace = root;
    slots[abi.BootstrapCaps.self_cnode] = s.Slot.initRoot(root);
    if (role == .terminal or role == .echo) {
        slots[1] = s.Slot.initRoot(.{ .endpoint = .{
            .object = objects.echo,
            .rights = .{ .read = role == .echo, .write = role == .terminal },
        } });
    }
    if (role != .echo) {
        slots[3] = s.Slot.initRoot(.{ .endpoint = .{
            .object = objects.filesystem,
            .rights = .{ .read = role == .filesystem, .write = role == .terminal },
        } });
    }
    if (role == .terminal or role == .probe) {
        slots[2] = s.Slot.initRoot(.{ .endpoint = .{
            .object = objects.fault,
            .badge = if (role == .probe) abi.fault_probe_badge else 0,
            .rights = .{ .read = role == .terminal, .write = role == .probe },
        } });
    }
    if (role == .probe) thread.fault_handler = 2;
    if (role == .terminal) {
        const caps = abi.BootstrapCaps;
        slots[caps.irq_wait] = s.Slot.initRoot(.{ .notification = .{
            .object = objects.irq,
            .rights = .{ .read = true, .write = false },
        } });
        slots[caps.self_tcb] = s.Slot.initRoot(.{ .tcb = thread });
        slots[caps.irq_control] = s.Slot.initRoot(.{ .irq_control = {} });
        slots[caps.irq_signal] = s.Slot.initRoot(.{ .notification = .{
            .object = objects.irq,
            .badge = 0x100,
            .rights = .{ .read = false, .write = true },
        } });
        slots[caps.untyped] = s.Slot.initRoot(.{ .untyped = .{ .memory = objects.untyped_memory } });
        thread.max_controlled_priority = 63;
    }
}

/// Place services on acknowledged CPUs before publishing their runnable state.
/// With only one CPU all tasks share it; with two CPUs both servers share the AP.
pub fn configureScheduling(thread: *s.Thread, role: Role, boot_cpu: u6, online: u64) void {
    const boot_mask = @as(u64, 1) << boot_cpu;
    std.debug.assert(online & boot_mask != 0);
    thread.priority = switch (role) {
        .filesystem => 30,
        .echo => 20,
        .terminal, .probe => 10,
    };

    var target = boot_cpu;
    if (role == .echo or role == .filesystem) {
        var auxiliary = online & ~boot_mask;
        if (auxiliary != 0) {
            target = @intCast(@ctz(auxiliary));
            if (role == .filesystem) {
                auxiliary &= auxiliary - 1;
                if (auxiliary != 0) target = @intCast(@ctz(auxiliary));
            }
        }
    }
    thread.affinity = @as(u64, 1) << target;
}
