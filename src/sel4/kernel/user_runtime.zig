//! Shared initial-task policy. CPU registers, page tables and exception return live in arch/.
const std = @import("std");
const abi = @import("terminal").abi;
const machine = @import("../arch/mod.zig").user;
const elf = @import("../boot/elf.zig");
const handoff = @import("../boot/handoff.zig");
const serial = @import("../platform/console.zig");
const s = @import("../model/structures.zig");
const Kernel = @import("runtime.zig").Kernel;
const syscalls = @import("../api/syscall.zig");
const Call = @import("../arch/user_call.zig").Call;
const Storage = @import("task_memory.zig").Storage;
const InfoPage = extern struct { value: abi.BootInfo = .{}, padding: [4096 - @sizeOf(abi.BootInfo)]u8 = @splat(0) };
const Task = struct {
    storage: Storage = undefined,
    tables: []machine.Table = undefined,
    space: machine.Space = undefined,
    image: []align(4096) u8 = undefined,
    stack: []align(4096) u8 = undefined,
    info: InfoPage align(4096) = .{},
    frame: machine.Frame = .{},
    thread: s.Thread = .{},
    slots: @import("../kernel/bootstrap_tasks.zig").Slots = @splat(.{}),
    pending_ipc: bool = false,
    native_abi: bool = false,
    ipc_buffer: s.IPCBuffer align(4096) = .{},
    entry: u64 = 0,
};
var tasks: [4]Task = undefined;
const smp_dispatch = @import("../kernel/smp_dispatch.zig");
var active: [64]usize = @splat(0);
fn activeIndex() usize {
    return active[smp_dispatch.index()];
}
var idle: s.Thread = .{};
var kernel: Kernel = undefined;
var endpoint: s.Endpoint = .{};
var filesystem_endpoint: s.Endpoint = .{};
var fault_endpoint: s.Endpoint = .{};
var irq_notification: s.Notification = .{};
fn switchTo(index: usize) *machine.Frame {
    active[smp_dispatch.index()] = index;
    const task = &tasks[index];
    if (task.pending_ipc) {
        if (task.native_abi) {
            @import("../api/native_ipc.zig").store(&task.thread, &task.ipc_buffer);
            machine.encodeNative(&task.frame, task.thread.badge, task.thread.message_info.words[0], task.thread.message[0..4].*);
        } else {
            var call = machine.decode(&task.frame);
            call.a = task.thread.badge;
            call.c = task.thread.message_info.words[0];
            @memcpy(&call.words, task.thread.message[0..4]);
            machine.encode(&task.frame, call);
        }
        task.pending_ipc = false;
    }
    if (!machine.faults.apply(&task.frame, &task.thread)) {
        kernel.suspendThread(&task.thread);
        return schedule();
    }
    task.space.activate();
    smp_dispatch.leave();
    return &task.frame;
}
fn readable(task: *Task, address: u64, length: u64) bool {
    return address >= abi.image_base and task.space.readable(address, length);
}
fn schedule() *machine.Frame {
    while (true) {
        const next = kernel.scheduler.schedule();
        for (&tasks, 0..) |*candidate, index| if (next == &candidate.thread) return switchTo(index);
        smp_dispatch.leave();
        @import("../platform/smp.zig").pollWork(smp_dispatch.index());
        @import("../arch/mod.zig").relax();
        smp_dispatch.enter(&kernel.scheduler);
    }
}
export fn terminal_arch_dispatch(incoming: *machine.Frame, kind: u64) callconv(.c) *machine.Frame {
    smp_dispatch.enter(&kernel.scheduler);
    if (machine.interrupt(incoming, kind)) |event| {
        tasks[activeIndex()].frame = incoming.*;
        @import("irq_dispatch.zig").handle(&kernel, event);
        if (event == .timer and activeIndex() == 3 and tasks[3].info.value.probe_kind == 0) {
            kernel.scheduler.block(&tasks[3].thread, .inactive);
            var result = machine.decode(&tasks[0].frame);
            result.value = 1;
            machine.encode(&tasks[0].frame, result);
        }
        return schedule();
    }
    if (machine.exception(incoming)) |fault| {
        const task = &tasks[activeIndex()];
        task.frame = incoming.*;
        task.thread.fault_pc = incoming.pc;
        task.thread.fault = fault;
        machine.faults.capture(&task.frame, &task.thread, false);
        // VM faults use all four message registers and require no IPC buffer.
        @import("../api/fault_ipc.zig").deliver(&kernel.scheduler, &task.thread) catch {};
        return schedule();
    }
    const task = &tasks[activeIndex()];
    task.frame = incoming.*;
    if (machine.isNative(&task.frame)) return dispatchNative(task);
    task.native_abi = false;
    task.thread.has_ipc_buffer = false;
    var c = machine.decode(&task.frame);
    const operation = std.enums.fromInt(abi.Operation, c.value);
    const access = activeIndex() == 0 and c.a == task.info.value.console_cap;
    c.value = std.math.maxInt(u64);
    if (operation) |op| switch (op) {
        .irq => if (access) {
            const controller = @import("../arch/mod.zig").backend.irq;
            if (c.b == 0) {
                controller.probeSource(true);
                c.value = 0;
            } else if (c.b == 1) {
                controller.probeSource(false);
                c.value = 0;
            }
        },
        .where => if (activeIndex() == 3) {
            c.value = smp_dispatch.index();
        },
        .migrate => if (access) {
            const probe = &tasks[3];
            if (c.b == 0 and c.c < 64 and probe.thread.owner_cpu == null) {
                const target = @as(u64, 1) << @as(u6, @intCast(c.c));
                if (target & kernel.scheduler.online_mask != 0) {
                    probe.info.value.probe_kind = 2;
                    probe.frame = machine.initial(probe.entry, abi.stack_base + abi.stack_size, abi.info_base);
                    probe.pending_ipc = false;
                    probe.thread.affinity = target;
                    kernel.scheduler.makeRunnable(&probe.thread);
                    c.value = 0;
                }
            } else if (c.b == 1 and probe.thread.state == .blocked_reply) {
                kernel.suspendThread(&probe.thread);
                probe.thread.affinity = tasks[0].thread.affinity;
                c.value = 0;
            }
        },
        .tlb => if (access) {
            if (@import("tlb_probe.zig").run(machine.Space, &tasks[3].space, abi.image_base + 0x900000)) |_| {
                c.value = 0;
            } else |err| {
                var buffer: [96]u8 = undefined;
                serial.serialWriteSlice(std.fmt.bufPrint(&buffer, "TLB probe: {s}\r\n", .{@errorName(err)}) catch "TLB probe failed\r\n");
            }
        },
        .fault => if (access) {
            const probe = &tasks[3];
            switch (c.b) {
                0 => {
                    probe.info.value.probe_kind = 1;
                    probe.pending_ipc = false;
                    probe.frame = machine.initial(probe.entry, abi.stack_base + abi.stack_size, abi.info_base);
                    probe.thread.fault = .{ .none = {} };
                    kernel.scheduler.makeRunnable(&probe.thread);
                    c.value = 0;
                },
                1 => if (probe.thread.state == .blocked_reply and probe.thread.fault == .vm) {
                    const data: *u64 = @ptrCast(probe.stack.ptr);
                    data.* = abi.fault_probe_value;
                    probe.space.map(abi.fault_probe_address, probe.storage.stack.address, true, false) catch return schedule();
                    c.value = 0;
                },
                2 => {
                    kernel.suspendThread(&probe.thread);
                    _ = probe.space.unmapPage(abi.fault_probe_address) catch return schedule();
                    @import("../platform/tlb_shootdown.zig").invalidateAll() catch @panic("fault probe shootdown failed");
                    c.value = 0;
                },
                3, 4 => if (probe.thread.state == .inactive and probe.thread.owner_cpu == null) {
                    // Start from a clean frame so old IPC results cannot overwrite a fault reply.
                    probe.info.value.probe_kind = c.b;
                    probe.pending_ipc = false;
                    probe.thread.fault = .{ .none = {} };
                    probe.frame = machine.initial(probe.entry, abi.stack_base + abi.stack_size, abi.info_base);
                    kernel.scheduler.makeRunnable(&probe.thread);
                    c.value = 0;
                },
                else => {},
            }
        },
        .preempt => if (access) {
            const probe = &tasks[3];
            probe.info.value.probe_kind = 0;
            probe.pending_ipc = false;
            probe.frame = machine.initial(probe.entry, abi.stack_base + abi.stack_size, abi.info_base);
            probe.thread.time_slice = 1;
            kernel.scheduler.makeRunnable(&probe.thread);
            c.value = 0;
            kernel.scheduler.yield();
        },
        .read => if (access) {
            if (serial.poll()) |byte| c.value = byte;
        },
        .write => if (access and readable(task, c.b, c.c)) {
            if (c.c != 0) serial.serialWriteSlice(@as([*]const u8, @ptrFromInt(c.b))[0..@intCast(c.c)]);
            c.value = 0;
        },
        .system => if (access and c.words[0] == 2 and c.c <= 256 and readable(task, c.b, c.c)) {
            if (@import("../fs/service.zig").run(c.words[0], @as([*]const u8, @ptrFromInt(c.b))[0..@intCast(c.c)])) c.value = 0;
        },
        .selftest => if (access) {
            if (@import("selftest.zig").run()) |_| {
                c.value = 0;
            } else |_| {}
        },
        .smp => if (access) {
            if (@import("../platform/smp.zig").selfTest()) |_| {
                c.value = @import("../platform/runtime.zig").topology.onlineCount();
            } else |_| {}
        },
        .block => if (activeIndex() == 2 and c.a == task.info.value.disk_cap and readable(task, c.b, 512) and
            (c.words[0] != 0 or task.space.writable(c.b, 512)))
        {
            const device = @import("../drivers/virtio_block.zig");
            const buffer: *[512]u8 = @ptrFromInt(c.b);
            const result = switch (c.words[0]) {
                0 => device.read(c.c, buffer),
                1 => device.write(c.c, buffer),
                4 => device.flush(),
                else => error.InvalidOperation,
            };
            if (result) |_| {
                c.value = 0;
            } else |err| {
                @import("../platform/console.zig").serialWriteSlice("block request failed: ");
                @import("../platform/console.zig").serialWriteSlice(@errorName(err));
                @import("../platform/console.zig").serialWriteSlice("\r\n");
            }
        },
        .ipc => if (c.c & 0xfff <= 4) {
            task.thread.message_info = .{ .words = .{c.c} };
            @memcpy(task.thread.message[0..4], &c.words);
            if (syscalls.dispatch(&kernel, @bitCast(c.a), c.b)) |_| {
                c.value = 0;
                task.pending_ipc = true;
            } else |_| {}
        },
    };
    machine.encode(&task.frame, c);
    return schedule();
}
/// The IPC page has a kernel alias, so extra words never dereference user pointers.
fn dispatchNative(task: *Task) *machine.Frame {
    const call = machine.decodeNative(&task.frame);
    const number: i64 = @bitCast(call.value);
    task.native_abi = true;
    task.thread.fault_pc = task.frame.pc - 4;
    machine.faults.capture(&task.frame, &task.thread, true);
    @import("../api/native_ipc.zig").load(&task.thread, &task.ipc_buffer, call.b, call.words);
    if (syscalls.dispatch(&kernel, number, call.a)) |_| {
        task.pending_ipc = true;
    } else |err| {
        task.pending_ipc = false;
        if (err == error.FailedLookup or err == error.InvalidCapability or err == error.ExtraCapLookup) {
            const address = if (err == error.ExtraCapLookup) task.thread.extra_cap_fault.? else call.a;
            @import("../api/syscall_fault.zig").lookup(&task.thread, number, address);
            task.frame.pc = task.thread.fault_pc;
        } else if (err != error.UnknownSyscall) {
            // Object decoder errors return an IllegalOperation label.
            task.thread.message_info = s.MessageInfo.init(3, 0, 0, 0);
            task.pending_ipc = true;
            return schedule();
        }
        @import("../api/fault_ipc.zig").deliver(&kernel.scheduler, &task.thread) catch {};
    }
    return schedule();
}
pub fn run(h: *const handoff.BootHandoff) !noreturn {
    if (h.ramdisk_address % 4096 != 0) return error.UnalignedSystemImage;
    kernel = Kernel.init(&idle);
    kernel.scheduler.online_mask = smp_dispatch.onlineMask();
    smp_dispatch.enter(&kernel.scheduler);
    // Keep retypable object storage in owned physical pages, outside the kernel image.
    const pool = &@import("../platform/runtime.zig").pages;
    const untyped_lease = try pool.allocatePages(16, 16);
    errdefer pool.release(untyped_lease) catch unreachable;
    var constructed: usize = 0;
    errdefer for (tasks[0..constructed]) |*task| task.storage.deinit();
    const arch = @tagName(@import("builtin").cpu.arch);
    for (&tasks, 0..) |*task, index| {
        var path: [96]u8 = undefined;
        const name = try std.fmt.bufPrint(&path, "/system/bin/{s}-{s}.elf", .{ if (index == 2) @as([]const u8, "fs") else "init", arch });
        const boot_file = try @import("../fs/system.zig").openBootFile(name, 2 * 1024 * 1024);
        defer boot_file.deinit();
        const image = try elf.Image.initFor(boot_file.bytes, machine.elf_machine);
        if (image.start != abi.image_base or image.size() > 512 * 1024 or image.end > abi.stack_base) return error.InvalidUserImage;
        task.* = .{};
        task.storage = try Storage.init(&@import("../platform/runtime.zig").pages, image.size(), abi.stack_size, 96);
        constructed += 1;
        task.image = task.storage.image.bytes();
        task.stack = task.storage.stack.bytes();
        const tables: [*]machine.Table = @ptrCast(task.storage.tables.bytes().ptr);
        task.tables = tables[0..96];
        task.space = try machine.Space.init(task.tables);
        const entry = try image.load(task.image[0..image.size()], image.start);
        for (0..image.header.phnum) |i| {
            const segment = try image.phdr(i);
            if (segment.type != .LOAD or segment.memsz == 0) continue;
            const writable = segment.flags.W;
            const executable = segment.flags.X;
            if (writable and executable) return error.WritableExecutableSegment;
            var page = segment.vaddr & ~@as(u64, 4095);
            while (page < segment.vaddr + segment.memsz) : (page += 4096)
                try task.space.map(page, task.storage.image.address + page - image.start, writable, executable);
        }
        for (0..abi.stack_size / 4096) |i| try task.space.map(abi.stack_base + i * 4096, task.storage.stack.address + i * 4096, true, false);
        @import("../boot/console.zig").fillInfo(&task.info.value, h);
        task.info.value.role = index;
        if (index == 2) {
            task.info.value.ramdisk_size = h.ramdisk_size;
            const pages = std.mem.alignForward(u64, h.ramdisk_size, 4096) / 4096;
            for (0..@intCast(pages)) |i| try task.space.map(abi.ramdisk_base + i * 4096, h.ramdisk_address + i * 4096, false, false);
        }
        if (h.framebuffer.address != 0) {
            var address = h.framebuffer.address & ~@as(u64, 4095);
            const end = std.mem.alignForward(u64, h.framebuffer.address + h.framebuffer.byte_size, 4096);
            while (address < end) : (address += 4096) try task.space.mapKernel(address, address);
        }
        try task.space.map(abi.info_base, machine.physical(@intFromPtr(&task.info)), false, false);
        try task.space.map(abi.ipc_base, machine.physical(@intFromPtr(&task.ipc_buffer)), true, false);
        task.entry = entry;
        task.frame = machine.initial(entry, abi.stack_base + abi.stack_size, abi.info_base);
        try @import("../kernel/bootstrap_tasks.zig").initialize(&task.slots, &task.thread, @fromBackingInt(@intCast(index)), .{
            .echo = &endpoint,
            .filesystem = &filesystem_endpoint,
            .fault = &fault_endpoint,
            .irq = &irq_notification,
            .untyped_memory = untyped_lease.bytes(),
        });
        @import("../kernel/bootstrap_tasks.zig").configureScheduling(
            &task.thread,
            @fromBackingInt(@intCast(index)),
            @intCast(@import("../platform/runtime.zig").topology.boot_index),
            kernel.scheduler.online_mask,
        );
        task.thread.user_context_ready = true;
        if (index != 3) kernel.scheduler.makeRunnable(&task.thread);
    }
    kernel.irqs.controller = @import("../arch/mod.zig").backend.irq.controller;
    @import("../arch/mod.zig").backend.irq.initialize();
    machine.initialize();
    @import("../arch/mod.zig").backend.irq.initializeLocal();
    @import("../platform/smp.zig").registerIpi();
    @import("../arch/mod.zig").backend.timer.initialize();
    serial.serialWriteSlice("boot: starting isolated user terminal, IPC server and filesystem server\r\n");
    @import("../platform/smp.zig").enableUsers(secondaryUsers);
    machine.restore(schedule());
}

fn secondaryUsers(_: usize) noreturn {
    smp_dispatch.enter(&kernel.scheduler);
    machine.initialize();
    @import("../arch/mod.zig").backend.irq.initializeLocal();
    @import("../platform/smp.zig").registerIpi();
    @import("../arch/mod.zig").backend.timer.initializeLocal();
    machine.restore(schedule());
}
