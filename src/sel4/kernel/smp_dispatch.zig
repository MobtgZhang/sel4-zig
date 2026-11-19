//! Serialize kernel object mutations while retaining independent CPU selections.
//! Contending CPUs service shootdowns and bounded jobs with interrupts masked.
const arch = @import("../arch/mod.zig");
const topology = &@import("../platform/runtime.zig").topology;
const Scheduler = @import("thread.zig").Scheduler;

// This pointer and the scheduler's selected CPU are protected by the same lock.
var selected: ?*Scheduler = null;
var lock: @import("../platform/sync.zig").SpinLock = .{};

pub fn index() u6 {
    const id = arch.currentHardwareId();
    for (topology.cpus[0..topology.count], 0..) |cpu, i| {
        if (cpu.hardware_id == id) return @intCast(i);
    }
    @panic("trap from an undiscovered CPU");
}

pub fn onlineMask() u64 {
    var result: u64 = 0;
    for (topology.cpus[0..topology.count], 0..) |cpu, i| {
        if (cpu.state == .online) result |= @as(u64, 1) << @as(u6, @intCast(i));
    }
    return result;
}

pub fn enter(scheduler: *Scheduler) void {
    const cpu = index();
    while (!lock.tryLock()) {
        // A lock owner can be waiting for this CPU's shootdown acknowledgement.
        // Servicing mailboxes here prevents a kernel-lock/shootdown deadlock.
        @import("../platform/smp.zig").pollWork(cpu);
        arch.relax();
    }
    scheduler.selectCpu(cpu);
    selected = scheduler;
}

pub fn leave() void {
    var wake = selected.?.wake_mask & ~(@as(u64, 1) << index());
    selected.?.wake_mask = 0;
    // Capture pending wakeups under the lock, then publish queue changes before
    // sending IPIs. A remote CPU may acquire the lock as soon as it is released.
    lock.unlock();
    while (wake != 0) {
        const cpu: u6 = @intCast(@ctz(wake));
        wake &= wake - 1;
        @import("../platform/smp.zig").kick(cpu);
    }
}
