//! Bring up hardware CPUs and execute bounded kernel work on dedicated stacks.
//! After bootstrap, each worker can enter the shared user scheduler on its own CPU.
const arch = @import("../arch/mod.zig");
const runtime = @import("runtime.zig");
const memory = @import("memory.zig");
const SpinLock = @import("sync.zig").SpinLock;
const State = enum(u32) { idle, reserved, queued, running, complete };
const Worker = struct {
    state: State = .idle,
    function: ?*const fn (usize) void = null,
    argument: usize = 0,
    stack: ?memory.Lease = null,
};
var user_entry: usize = 0;
var ipi_ready: [64]u8 = @splat(0);
pub fn registerIpi() void {
    @atomicStore(u8, &ipi_ready[@import("../kernel/smp_dispatch.zig").index()], 1, .release);
}
pub fn kick(index: usize) void {
    if (@atomicLoad(u8, &ipi_ready[index], .acquire) == 0) return;
    arch.backend.irq.sendIpi(runtime.topology.cpus[index].hardware_id);
}
var workers: [64]Worker align(64) = @splat(.{});
pub export var secondary_boot_stacks: [64]usize = @splat(0);
// Mailbox-based startup is serialized until the target acknowledges its index.
export var secondary_boot_index: usize = 0;

pub fn initialize() !void {
    const topology = &runtime.topology;
    for (topology.cpus[0..topology.count], 0..) |*cpu, index| {
        if (index == topology.boot_index) continue;
        const stack = try runtime.pages.allocatePages(32, 1);
        @memset(stack.bytes(), 0);
        workers[index].stack = stack;
        secondary_boot_stacks[index] = @intFromPtr(stack.bytes().ptr) + stack.bytes().len;
        secondary_boot_index = index;
        try topology.beginStart(index);
        arch.backend.dmaBarrier();
        arch.backend.smp.start(cpu.hardware_id, index) catch |err| {
            @atomicStore(@import("cpu.zig").State, &cpu.state, .failed, .release);
            // Keep the stack reserved: a timed-out firmware request may still run.
            return err;
        };
        const started = arch.backend.smp.ticks();
        while (@atomicLoad(@import("cpu.zig").State, &cpu.state, .acquire) != .online) {
            if (arch.backend.smp.ticks() -% started > arch.backend.smp.timeout_ticks) return error.CpuStartupTimeout;
            arch.relax();
        }
    }
}

export fn secondary_main(index: usize) callconv(.c) noreturn {
    if (index >= runtime.topology.count) arch.halt();
    runtime.topology.acknowledge(index, arch.currentHardwareId()) catch arch.halt();
    while (true) {
        pollWork(index);
        const entry = @atomicLoad(usize, &user_entry, .acquire);
        if (entry != 0) {
            const start: *const fn (usize) noreturn = @ptrFromInt(entry);
            start(index);
        }
        arch.relax();
    }
}
pub fn enableUsers(entry: *const fn (usize) noreturn) void {
    @atomicStore(usize, &user_entry, @intFromPtr(entry), .release);
}
pub fn pollWork(index: usize) void {
    @import("tlb_shootdown.zig").poll(index);
    const worker = &workers[index];
    if (@atomicLoad(State, &worker.state, .acquire) == .queued) {
        @atomicStore(State, &worker.state, .running, .monotonic);
        worker.function.?(worker.argument);
        @atomicStore(State, &worker.state, .complete, .release);
    }
}

pub fn submit(index: usize, function: *const fn (usize) void, argument: usize) !void {
    if (index >= runtime.topology.count or index == runtime.topology.boot_index or
        @atomicLoad(@import("cpu.zig").State, &runtime.topology.cpus[index].state, .acquire) != .online) return error.CpuOffline;
    const worker = &workers[index];
    const state = @atomicLoad(State, &worker.state, .acquire);
    if ((state != .idle and state != .complete) or
        @cmpxchgStrong(State, &worker.state, state, .reserved, .acquire, .monotonic) != null) return error.CpuBusy;
    worker.function = function;
    worker.argument = argument;
    @atomicStore(State, &worker.state, .queued, .release);
    kick(index);
}
pub fn wait(index: usize) !void {
    if (index >= runtime.topology.count or index == runtime.topology.boot_index) return error.CpuOffline;
    const started = arch.backend.smp.ticks();
    while (@atomicLoad(State, &workers[index].state, .acquire) != .complete) {
        if (arch.backend.smp.ticks() -% started > arch.backend.smp.timeout_ticks) return error.CpuWorkTimeout;
        arch.relax();
    }
}

var probe_lock: SpinLock = .{};
var selftest_lock: SpinLock = .{};
var probe_counter: usize = 0;
var probe_failed: u32 = 0;
fn probe(index: usize) void {
    for (0..2048) |_| {
        const flags = probe_lock.lockIrqSave();
        probe_counter += 1;
        probe_lock.unlockIrqRestore(flags);
    }
    const lease = runtime.pages.allocate() catch {
        @atomicStore(u32, &probe_failed, 1, .release);
        return;
    };
    @memset(lease.bytes(), @truncate(index + 1));
    for (lease.bytes()) |byte| if (byte != @as(u8, @truncate(index + 1))) {
        @atomicStore(u32, &probe_failed, 1, .release);
    };
    @memset(lease.bytes(), 0);
    runtime.pages.release(lease) catch {
        @atomicStore(u32, &probe_failed, 1, .release);
    };
}
/// Run on every online CPU, proving actual parallel lock and page-pool use.
pub fn selfTest() !void {
    if (!selftest_lock.tryLock()) return error.CpuBusy;
    defer selftest_lock.unlock();
    probe_counter = 0;
    probe_failed = 0;
    const topology = &runtime.topology;
    for (topology.cpus[0..topology.count], 0..) |cpu, index| {
        if (cpu.state == .online and index != topology.boot_index) try submit(index, probe, index);
    }
    probe(topology.boot_index);
    for (topology.cpus[0..topology.count], 0..) |cpu, index| {
        if (cpu.state == .online and index != topology.boot_index) try wait(index);
    }
    if (probe_counter != topology.onlineCount() * 2048 or probe_failed != 0) return error.CrossCpuSynchronizationFailed;
}
