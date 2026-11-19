//! Synchronous IPI shootdowns with polling fallback while IRQs are masked.
//! Requests bypass the work mailbox, so outstanding jobs cannot overwrite them.
const arch = @import("../arch/mod.zig");
const runtime = @import("runtime.zig");
const State = @import("cpu.zig").State;
const SpinLock = @import("sync.zig").SpinLock;
const Mailbox = struct { request: u64 = 0, acknowledged: u64 = 0 };
var mailboxes: [64]Mailbox align(64) = @splat(.{});
var lock: SpinLock = .{};
var generation: u64 = 0;
var poisoned = false;

/// Called even when no kernel job is queued. Acquire pairs with PTE publication.
pub fn poll(index: usize) void {
    const box = &mailboxes[index];
    const request = @atomicLoad(u64, &box.request, .acquire);
    if (request == @atomicLoad(u64, &box.acknowledged, .monotonic)) return;
    arch.backend.tlb.invalidateAll();
    @atomicStore(u64, &box.acknowledged, request, .release);
}

pub fn invalidateAll() error{ ShootdownBusy, ShootdownTimeout, ShootdownPoisoned }!void {
    if (!lock.tryLock()) return error.ShootdownBusy;
    defer lock.unlock();
    if (poisoned) return error.ShootdownPoisoned;
    generation +%= 1;
    if (generation == 0) generation = 1;
    var targets: u64 = 0;
    const hardware_id = arch.currentHardwareId();
    for (runtime.topology.cpus[0..runtime.topology.count], 0..) |*cpu, index| {
        if (cpu.hardware_id == hardware_id or @atomicLoad(State, &cpu.state, .acquire) != .online) continue;
        targets |= @as(u64, 1) << @as(u6, @intCast(index));
        @atomicStore(u64, &mailboxes[index].request, generation, .release);
        @import("smp.zig").kick(index);
    }
    arch.backend.tlb.invalidateAll();
    const begin = arch.backend.smp.ticks();
    while (targets != 0) {
        const index: u6 = @intCast(@ctz(targets));
        if (@atomicLoad(u64, &mailboxes[index].acknowledged, .acquire) == generation) {
            targets &= ~(@as(u64, 1) << index);
        } else if (arch.backend.smp.ticks() -% begin > arch.backend.smp.timeout_ticks) {
            // An unacknowledged core may still hold the old mapping. Never reuse pages.
            poisoned = true;
            return error.ShootdownTimeout;
        } else arch.relax();
    }
}
