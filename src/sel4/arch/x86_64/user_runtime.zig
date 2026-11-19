//! Four-task bootstrap runtime with owned physical image, stack and table pages.
//! Kernel memory remains supervisor-only; each task owns its image and stack.
const std = @import("std");
const shell = @import("terminal");
const abi = shell.abi;
const vm = @import("vspace.zig");
const elf = @import("../../boot/elf.zig");
const handoff = @import("../../boot/handoff.zig");
const serial = @import("../../platform/console.zig");
const s = @import("../../model/structures.zig");
const Kernel = @import("../../kernel/runtime.zig").Kernel;
const syscalls = @import("../../api/syscall.zig");
const IdtEntry = @import("idt.zig").IdtEntry;
const Storage = @import("../../kernel/task_memory.zig").Storage;
extern fn x86_load_user_gdt(*const [10]u8) callconv(.c) void;
extern fn x86_restore_user(*const Frame) callconv(.c) noreturn;
extern fn x86_terminal_trap() void;
extern fn x86_native_syscall() void;
extern fn x86_timer_trap() void;
extern fn x86_ipi_trap() void;
extern const x86_device_vectors: [15]i32;
extern fn x86_local_timer_trap() void;
extern fn x86_spurious_trap() void;
extern fn x86_user_gp() void;
extern fn x86_user_ud() void;
extern fn x86_user_de() void;
extern fn x86_user_pf() void;
extern fn x86_lidt(*const [10]u8) callconv(.c) void;

pub const Frame = extern struct {
    r15: u64 = 0,
    r14: u64 = 0,
    r13: u64 = 0,
    r12: u64 = 0,
    r11: u64 = 0,
    r10: u64 = 0,
    r9: u64 = 0,
    r8: u64 = 0,
    rbp: u64 = 0,
    rdi: u64 = 0,
    rsi: u64 = 0,
    rdx: u64 = 0,
    rcx: u64 = 0,
    rbx: u64 = 0,
    rax: u64 = 0,
    rip: u64 = 0,
    cs: u64 = 0x23,
    rflags: u64 = 0x202,
    rsp: u64 = 0,
    ss: u64 = 0x1b,
};
comptime {
    std.debug.assert(@sizeOf(Frame) == 160 and @offsetOf(Frame, "rip") == 120);
}
const InfoPage = extern struct {
    value: abi.BootInfo = .{},
    padding: [4096 - @sizeOf(abi.BootInfo)]u8 = @splat(0),
};
comptime {
    std.debug.assert(@sizeOf(InfoPage) == 4096);
}
const Task = struct {
    storage: Storage = undefined,
    tables: []vm.Table = undefined,
    space: vm.AddressSpace = undefined,
    image: []align(4096) u8 = undefined,
    stack: []align(4096) u8 = undefined,
    info: InfoPage align(4096) = .{},
    fpu: [512]u8 align(16) = @splat(0),
    frame: Frame = .{},
    thread: s.Thread = .{},
    slots: @import("../../kernel/bootstrap_tasks.zig").Slots = @splat(.{}),
    pending_ipc: bool = false,
    native_abi: bool = false,
    ipc_buffer: s.IPCBuffer align(4096) = .{},
    entry: u64 = 0,
};
var tasks: [4]Task = undefined;
const smp_dispatch = @import("../../kernel/smp_dispatch.zig");
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
var kernel_stack: [128 * 1024]u8 align(16) = undefined;
const CpuContext = extern struct {
    stack_top: usize = 0,
    user_sp: usize = 0,
    fpu: usize = 0,
    gdt: [7]u64 = @splat(0),
    tss: [104]u8 = @splat(0),
};
var cpu_contexts: [64]CpuContext align(64) = @splat(.{});
var idt: [256]IdtEntry align(16) = undefined;

fn descriptor(base: usize, limit: u16) [10]u8 {
    var bytes: [10]u8 = undefined;
    std.mem.writeInt(u16, bytes[0..2], limit, .little);
    std.mem.writeInt(u64, bytes[2..10], base, .little);
    return bytes;
}
fn installGates(cpu: u6) void {
    const context = &cpu_contexts[cpu];
    const gdt = &context.gdt;
    const tss = &context.tss;
    const bsp = @import("../../platform/runtime.zig").topology.boot_index;
    context.stack_top = if (cpu == bsp) @intFromPtr(&kernel_stack) + kernel_stack.len else @import("../../platform/smp.zig").secondary_boot_stacks[cpu];
    @import("machine.zig").wrmsr(0xc0000101, @intFromPtr(context));
    @import("machine.zig").wrmsr(0xc0000102, 0);
    gdt[1] = 0x00af9a000000ffff;
    gdt[2] = 0x00cf92000000ffff;
    gdt[3] = 0x00cff2000000ffff;
    gdt[4] = 0x00affa000000ffff;
    const base = @intFromPtr(tss);
    gdt[5] = 103 | ((base & 0xffffff) << 16) | (@as(u64, 0x89) << 40) | (((base >> 24) & 0xff) << 56);
    gdt[6] = base >> 32;
    std.mem.writeInt(u64, tss[4..12], context.stack_top, .little);
    // No userspace I/O permissions: the bitmap starts beyond the TSS limit.
    std.mem.writeInt(u16, tss[102..104], 104, .little);
    const gdtr = descriptor(@intFromPtr(gdt), @sizeOf(@TypeOf(gdt.*)) - 1);
    @import("machine.zig").wrmsr(0xc0000080, @import("machine.zig").rdmsr(0xc0000080) | 1);
    @import("machine.zig").wrmsr(0xc0000081, (@as(u64, 0x13) << 48) | (@as(u64, 8) << 32));
    @import("machine.zig").wrmsr(0xc0000082, @intFromPtr(&x86_native_syscall));
    @import("machine.zig").wrmsr(0xc0000084, 0x600);
    x86_load_user_gdt(&gdtr);
    if (cpu == bsp) {
        @memset(std.mem.asBytes(&idt), 0);
        idt[0] = IdtEntry.initInterruptGate(8, @intFromPtr(&x86_user_de), 0);
        idt[6] = IdtEntry.initInterruptGate(8, @intFromPtr(&x86_user_ud), 0);
        idt[13] = IdtEntry.initInterruptGate(8, @intFromPtr(&x86_user_gp), 0);
        idt[14] = IdtEntry.initInterruptGate(8, @intFromPtr(&x86_user_pf), 0);
        for (x86_device_vectors, 33..) |address, vector| idt[vector] = IdtEntry.initInterruptGate(8, @intCast(@as(i64, @intCast(@intFromPtr(&x86_device_vectors))) + address), 0);
        idt[240] = IdtEntry.initInterruptGate(8, @intFromPtr(&x86_ipi_trap), 0);
        idt[32] = IdtEntry.initInterruptGate(8, @intFromPtr(&x86_timer_trap), 0);
        idt[48] = IdtEntry.initInterruptGate(8, @intFromPtr(&x86_local_timer_trap), 0);
        idt[255] = IdtEntry.initInterruptGate(8, @intFromPtr(&x86_spurious_trap), 0);
        idt[128] = IdtEntry.initInterruptGate(8, @intFromPtr(&x86_terminal_trap), 3);
    }
    const idtr = descriptor(@intFromPtr(&idt), @sizeOf(@TypeOf(idt)) - 1);
    x86_lidt(&idtr);
}
fn switchTo(index: usize) *Frame {
    active[smp_dispatch.index()] = index;
    const task = &tasks[index];
    if (task.pending_ipc) {
        if (task.native_abi) {
            @import("../../api/native_ipc.zig").store(&task.thread, &task.ipc_buffer);
            const f = &task.frame;
            f.rdi = task.thread.badge;
            f.rsi = task.thread.message_info.words[0];
            f.r10 = task.thread.message[0];
            f.r8 = task.thread.message[1];
            f.r9 = task.thread.message[2];
            f.r15 = task.thread.message[3];
        } else {
            task.frame.rdi = task.thread.badge;
            task.frame.rdx = task.thread.message_info.words[0];
            task.frame.r10 = task.thread.message[0];
            task.frame.r8 = task.thread.message[1];
            task.frame.r9 = task.thread.message[2];
            task.frame.r15 = task.thread.message[3];
        }
        task.pending_ipc = false;
    }
    if (!@import("fault.zig").apply(&task.frame, &task.thread)) {
        kernel.suspendThread(&task.thread);
        return schedule();
    }
    cpu_contexts[smp_dispatch.index()].fpu = @intFromPtr(&task.fpu);
    asm volatile ("mov %[root], %%cr3"
        :
        : [root] "r" (task.space.physical_base),
        : .{ .memory = true });
    smp_dispatch.leave();
    return &task.frame;
}
fn schedule() *Frame {
    while (true) {
        const next = kernel.scheduler.schedule();
        for (&tasks, 0..) |*candidate, index| if (next == &candidate.thread) return switchTo(index);
        smp_dispatch.leave();
        @import("../../platform/smp.zig").pollWork(smp_dispatch.index());
        @import("../../arch/mod.zig").relax();
        smp_dispatch.enter(&kernel.scheduler);
    }
}
export fn terminal_timer_dispatch(incoming: *const Frame) callconv(.c) *Frame {
    smp_dispatch.enter(&kernel.scheduler);
    if (incoming.cs & 3 != 3) @panic("kernel IRQ on user exception stack");
    if (smp_dispatch.index() == @import("../../platform/runtime.zig").topology.boot_index)
        @import("timer.zig").acknowledge()
    else
        @import("timer.zig").acknowledgeLocal();
    tasks[activeIndex()].frame = incoming.*;
    kernel.scheduler.timerTick();
    if (activeIndex() == 3 and tasks[3].info.value.probe_kind == 0) {
        kernel.scheduler.block(&tasks[3].thread, .inactive);
        tasks[0].frame.rax = 1;
    }
    return schedule();
}
export fn terminal_ipi_dispatch(incoming: *const Frame) callconv(.c) *Frame {
    @import("irq.zig").acknowledgeIpi();
    smp_dispatch.enter(&kernel.scheduler);
    if (incoming.cs & 3 != 3) @panic("kernel IPI on user exception stack");
    tasks[activeIndex()].frame = incoming.*;
    @import("../../kernel/irq_dispatch.zig").handle(&kernel, .ipi);
    return schedule();
}
export fn terminal_device_dispatch(raw: [*]const u64) callconv(.c) *Frame {
    smp_dispatch.enter(&kernel.scheduler);
    if (raw[18] & 3 != 3) @panic("kernel device IRQ on user exception stack");
    const destination: [*]u64 = @ptrCast(&tasks[activeIndex()].frame);
    @memcpy(destination[0..15], raw[0..15]);
    @memcpy(destination[15..20], raw[17..22]);
    @import("../../kernel/irq_dispatch.zig").handle(&kernel, .{ .device = @intCast(raw[15] - 32) });
    return schedule();
}
export fn terminal_exception_dispatch(raw: [*]const u64) callconv(.c) *Frame {
    smp_dispatch.enter(&kernel.scheduler);
    const vector = raw[15];
    const error_code = raw[16];
    if (raw[18] & 3 != 3) terminal_fatal_fault(vector, error_code, raw[17]);
    const task = &tasks[activeIndex()];
    const destination: [*]u64 = @ptrCast(&task.frame);
    @memcpy(destination[0..15], raw[0..15]);
    @memcpy(destination[15..20], raw[17..22]);
    task.thread.fault_pc = task.frame.rip;
    task.thread.fault = if (vector == 14) .{ .vm = .{
        .address = asm volatile ("mov %%cr2, %[v]"
            : [v] "=r" (-> u64),
        ),
        .status = error_code,
        .instruction = error_code & 16 != 0,
    } } else .{ .user_exception = .{ .number = vector, .code = error_code } };
    @import("fault.zig").capture(&task.frame, &task.thread, false);
    @import("../../api/fault_ipc.zig").deliver(&kernel.scheduler, &task.thread) catch {};
    return schedule();
}
export fn terminal_native_dispatch(incoming: *const Frame) callconv(.c) *Frame {
    smp_dispatch.enter(&kernel.scheduler);
    const task = &tasks[activeIndex()];
    task.frame = incoming.*;
    task.native_abi = true;
    const f = &task.frame;
    const number: i64 = @bitCast(f.rdx);
    task.thread.fault_pc = f.rip - 2;
    @import("fault.zig").capture(f, &task.thread, true);
    @import("../../api/native_ipc.zig").load(&task.thread, &task.ipc_buffer, f.rsi, .{ f.r10, f.r8, f.r9, f.r15 });
    if (syscalls.dispatch(&kernel, number, f.rdi)) |_| {
        task.pending_ipc = true;
    } else |err| {
        task.pending_ipc = false;
        if (err == error.FailedLookup or err == error.InvalidCapability or err == error.ExtraCapLookup) {
            const address = if (err == error.ExtraCapLookup) task.thread.extra_cap_fault.? else f.rdi;
            @import("../../api/syscall_fault.zig").lookup(&task.thread, number, address);
            f.rip = task.thread.fault_pc;
        } else if (err != error.UnknownSyscall) {
            task.thread.message_info = s.MessageInfo.init(3, 0, 0, 0);
            task.pending_ipc = true;
            return schedule();
        }
        @import("../../api/fault_ipc.zig").deliver(&kernel.scheduler, &task.thread) catch {};
    }
    return schedule();
}
export fn terminal_dispatch(incoming: *const Frame) callconv(.c) *Frame {
    smp_dispatch.enter(&kernel.scheduler);
    const task = &tasks[activeIndex()];
    task.frame = incoming.*;
    task.native_abi = false;
    task.thread.has_ipc_buffer = false;
    const f = &task.frame;
    const operation = std.enums.fromInt(abi.Operation, f.rax) orelse {
        f.rax = std.math.maxInt(u64);
        return switchTo(activeIndex());
    };
    // Console authority is a bootstrap service handle, separate from endpoint CSpace.
    const console_access = activeIndex() == 0 and f.rdi == task.info.value.console_cap;
    f.rax = std.math.maxInt(u64);
    switch (operation) {
        .irq => if (console_access) {
            const controller = @import("../../arch/mod.zig").backend.irq;
            if (f.rsi == 0) {
                controller.probeSource(true);
                f.rax = 0;
            } else if (f.rsi == 1) {
                controller.probeSource(false);
                f.rax = 0;
            }
        },
        .where => if (activeIndex() == 3) {
            f.rax = smp_dispatch.index();
        },
        .migrate => if (console_access) {
            const probe = &tasks[3];
            if (f.rsi == 0 and f.rdx < 64 and probe.thread.owner_cpu == null) {
                const target = @as(u64, 1) << @as(u6, @intCast(f.rdx));
                if (target & kernel.scheduler.online_mask != 0) {
                    probe.info.value.probe_kind = 2;
                    probe.frame = .{ .rip = probe.entry, .rsp = abi.stack_base + abi.stack_size - 8, .rdi = abi.info_base };
                    probe.pending_ipc = false;
                    probe.thread.affinity = target;
                    kernel.scheduler.makeRunnable(&probe.thread);
                    f.rax = 0;
                }
            } else if (f.rsi == 1 and probe.thread.state == .blocked_reply) {
                kernel.suspendThread(&probe.thread);
                probe.thread.affinity = tasks[0].thread.affinity;
                f.rax = 0;
            }
        },
        .tlb => if (console_access) {
            if (@import("../../kernel/tlb_probe.zig").run(vm.AddressSpace, &tasks[3].space, abi.image_base + 0x900000)) |_| {
                f.rax = 0;
            } else |_| {}
        },
        .fault => if (console_access) {
            const probe = &tasks[3];
            switch (f.rsi) {
                0 => {
                    probe.info.value.probe_kind = 1;
                    probe.pending_ipc = false;
                    probe.frame = .{ .rip = probe.entry, .rsp = abi.stack_base + abi.stack_size - 8, .rdi = abi.info_base };
                    probe.thread.fault = .{ .none = {} };
                    kernel.scheduler.makeRunnable(&probe.thread);
                    f.rax = 0;
                },
                1 => if (probe.thread.state == .blocked_reply and probe.thread.fault == .vm) {
                    const data: *u64 = @ptrCast(probe.stack.ptr);
                    data.* = abi.fault_probe_value;
                    probe.space.map(abi.fault_probe_address, probe.storage.stack.address, .small, true, false, true) catch return schedule();
                    f.rax = 0;
                },
                2 => {
                    kernel.suspendThread(&probe.thread);
                    _ = probe.space.unmapPage(abi.fault_probe_address) catch return schedule();
                    @import("../../platform/tlb_shootdown.zig").invalidateAll() catch @panic("fault probe shootdown failed");
                    f.rax = 0;
                },
                3, 4 => if (probe.thread.state == .inactive and probe.thread.owner_cpu == null) {
                    // Start from a clean frame so old IPC results cannot overwrite a fault reply.
                    probe.info.value.probe_kind = f.rsi;
                    probe.pending_ipc = false;
                    probe.thread.fault = .{ .none = {} };
                    probe.frame = .{ .rip = probe.entry, .rsp = abi.stack_base + abi.stack_size - 8, .rdi = abi.info_base };
                    kernel.scheduler.makeRunnable(&probe.thread);
                    f.rax = 0;
                },
                else => {},
            }
        },
        .preempt => if (console_access) {
            const probe = &tasks[3];
            probe.info.value.probe_kind = 0;
            probe.pending_ipc = false;
            probe.frame = .{ .rip = probe.entry, .rsp = abi.stack_base + abi.stack_size - 8, .rdi = abi.info_base };
            probe.thread.time_slice = 1;
            kernel.scheduler.makeRunnable(&probe.thread);
            f.rax = 0;
            kernel.scheduler.yield();
        },
        .read => if (console_access) {
            if (serial.poll()) |byte| f.rax = byte;
        },
        .write => if (console_access and @import("user_memory.zig").readable(&task.space, abi.image_base, f.rsi, f.rdx)) {
            if (f.rdx != 0) serial.serialWriteSlice(@as([*]const u8, @ptrFromInt(f.rsi))[0..@intCast(f.rdx)]);
            f.rax = 0;
        },
        .system => if (console_access and f.r10 == 2 and f.rdx <= 256 and @import("user_memory.zig").readable(&task.space, abi.image_base, f.rsi, f.rdx)) {
            if (@import("../../fs/service.zig").run(f.r10, @as([*]const u8, @ptrFromInt(f.rsi))[0..@intCast(f.rdx)])) f.rax = 0;
        },
        .selftest => if (console_access) {
            if (@import("../../kernel/selftest.zig").run()) |_| {
                f.rax = 0;
            } else |_| {}
        },
        .smp => if (console_access) {
            if (@import("../../platform/smp.zig").selfTest()) |_| {
                f.rax = @import("../../platform/runtime.zig").topology.onlineCount();
            } else |_| {}
        },
        .block => if (activeIndex() == 2 and f.rdi == task.info.value.disk_cap and @import("user_memory.zig").readable(&task.space, abi.image_base, f.rsi, 512) and
            (f.r10 != 0 or @import("user_memory.zig").writable(&task.space, abi.image_base, f.rsi, 512)))
        {
            const device = @import("../../drivers/virtio_block.zig");
            const buffer: *[512]u8 = @ptrFromInt(f.rsi);
            const result = switch (f.r10) {
                0 => device.read(f.rdx, buffer),
                1 => device.write(f.rdx, buffer),
                4 => device.flush(),
                else => error.InvalidOperation,
            };
            if (result) |_| {
                f.rax = 0;
            } else |err| {
                serial.serialWriteSlice("block request failed: ");
                serial.serialWriteSlice(@errorName(err));
                serial.serialWriteSlice("\r\n");
            }
        },
        .ipc => {
            // This bootstrap ABI has register messages only and transfers no caps.
            if (f.rdx & 0xfff > 4) return switchTo(activeIndex());
            task.thread.message_info = .{ .words = .{f.rdx} };
            @memcpy(task.thread.message[0..4], &[_]u64{ f.r10, f.r8, f.r9, f.r15 });
            if (syscalls.dispatch(&kernel, @bitCast(f.rdi), f.rsi)) |_| {
                f.rax = 0;
                task.pending_ipc = true;
            } else |_| {}
        },
    }
    return schedule();
}
export fn terminal_fatal_fault(vector: u64, code: u64, rip: u64) callconv(.c) noreturn {
    var buffer: [128]u8 = undefined;
    serial.serialWriteSlice(std.fmt.bufPrint(&buffer, "PANIC: x86 exception {d} code=0x{x} rip=0x{x}\r\n", .{ vector, code, rip }) catch "PANIC: x86 exception\r\n");
    while (true) asm volatile ("hlt");
}
pub fn run(h: *const handoff.BootHandoff) !noreturn {
    // Boot loaders supply identity mappings for the kernel image and static storage.
    const old_cr3 = asm volatile ("mov %%cr3, %[root]"
        : [root] "=r" (-> u64),
    );
    const old_root: *const vm.Table = @ptrFromInt(old_cr3 & vm.physical_mask);
    if (old_root.entries[vm.virtPageTableIndex(abi.image_base, 3)] & vm.pte_present != 0) return error.UserAddressConflict;
    const extended = asm volatile ("cpuid"
        : [features] "={edx}" (-> u32),
        : [leaf] "{eax}" (@as(u32, 0x80000001)),
        : .{ .eax = true, .ebx = true, .ecx = true });
    if (extended & (1 << 20) == 0) return error.ExecuteDisableUnavailable;
    // Enable execute-disable pages and write protection before exposing user mappings.
    asm volatile ("rdmsr\n\tor $0x800, %%eax\n\twrmsr"
        :
        : [msr] "{ecx}" (@as(u32, 0xc0000080)),
        : .{ .rax = true, .rdx = true, .memory = true });
    const cr0 = asm volatile ("mov %%cr0, %[value]"
        : [value] "=r" (-> u64),
    );
    asm volatile ("mov %[value], %%cr0"
        :
        : [value] "r" (cr0 | (1 << 16)),
        : .{ .memory = true });
    if (h.ramdisk_address % 4096 != 0) return error.UnalignedSystemImage;
    kernel = Kernel.init(&idle);
    kernel.scheduler.online_mask = smp_dispatch.onlineMask();
    smp_dispatch.enter(&kernel.scheduler);
    // Keep retypable object storage in owned physical pages, outside the kernel image.
    const pool = &@import("../../platform/runtime.zig").pages;
    const untyped_lease = try pool.allocatePages(16, 16);
    errdefer pool.release(untyped_lease) catch unreachable;
    var constructed: usize = 0;
    errdefer for (tasks[0..constructed]) |*task| task.storage.deinit();
    for (&tasks, 0..) |*task, index| {
        const boot_file = try @import("../../fs/system.zig").openBootFile(if (index == 2) "/system/bin/fs.elf" else "/system/bin/init.elf", 2 * 1024 * 1024);
        defer boot_file.deinit();
        const image = try elf.Image.init(boot_file.bytes);
        if (image.start != abi.image_base or image.size() > 512 * 1024 or image.end > abi.stack_base) return error.InvalidUserImage;
        task.* = .{};
        task.storage = try Storage.init(&@import("../../platform/runtime.zig").pages, image.size(), abi.stack_size, 80);
        constructed += 1;
        task.image = task.storage.image.bytes();
        task.stack = task.storage.stack.bytes();
        const tables: [*]vm.Table = @ptrCast(task.storage.tables.bytes().ptr);
        task.tables = tables[0..80];
        task.space = try vm.AddressSpace.init(task.tables, task.storage.tables.address);
        for (old_root.entries, 0..) |entry, i| task.tables[0].entries[i] = entry & ~vm.pte_us;
        const entry = try image.load(task.image[0..image.size()], image.start);
        for (0..image.header.phnum) |i| {
            const segment = try image.phdr(i);
            if (segment.type != .LOAD or segment.memsz == 0) continue;
            const writable = segment.flags.W;
            const executable = segment.flags.X;
            if (writable and executable) return error.WritableExecutableSegment;
            var page = segment.vaddr & ~@as(u64, 4095);
            while (page < segment.vaddr + segment.memsz) : (page += 4096) {
                try task.space.map(page, task.storage.image.address + page - image.start, .small, writable, executable, true);
            }
        }
        for (0..abi.stack_size / 4096) |i| try task.space.map(abi.stack_base + i * 4096, task.storage.stack.address + i * 4096, .small, true, false, true);
        @import("../../boot/console.zig").fillInfo(&task.info.value, h);
        task.info.value.role = index;
        if (index == 2) {
            task.info.value.ramdisk_size = h.ramdisk_size;
            const pages = std.mem.alignForward(u64, h.ramdisk_size, 4096) / 4096;
            for (0..@intCast(pages)) |i| try task.space.map(abi.ramdisk_base + i * 4096, h.ramdisk_address + i * 4096, .small, false, false, true);
        }
        try task.space.map(abi.info_base, @intFromPtr(&task.info), .small, false, false, true);
        try task.space.map(abi.ipc_base, @intFromPtr(&task.ipc_buffer), .small, true, false, true);
        task.entry = entry;
        task.frame = .{ .rip = entry, .rsp = abi.stack_base + abi.stack_size - 8, .rdi = abi.info_base };
        try @import("../../kernel/bootstrap_tasks.zig").initialize(&task.slots, &task.thread, @fromBackingInt(@intCast(index)), .{
            .echo = &endpoint,
            .filesystem = &filesystem_endpoint,
            .fault = &fault_endpoint,
            .irq = &irq_notification,
            .untyped_memory = untyped_lease.bytes(),
        });
        @import("../../kernel/bootstrap_tasks.zig").configureScheduling(
            &task.thread,
            @fromBackingInt(@intCast(index)),
            @intCast(@import("../../platform/runtime.zig").topology.boot_index),
            kernel.scheduler.online_mask,
        );
        task.thread.user_context_ready = true;
        if (index != 3) kernel.scheduler.makeRunnable(&task.thread);
        // Start with clean x87/SSE registers instead of exposing kernel SIMD data.
        @memset(&task.fpu, 0);
        std.mem.writeInt(u16, task.fpu[0..2], 0x037f, .little);
        std.mem.writeInt(u32, task.fpu[24..28], 0x1f80, .little);
    }
    kernel.irqs.controller = @import("../../arch/mod.zig").backend.irq.controller;
    @import("../../arch/mod.zig").backend.irq.initialize();
    installGates(smp_dispatch.index());
    @import("../../arch/mod.zig").backend.irq.initializeLocal();
    @import("../../platform/smp.zig").registerIpi();
    @import("timer.zig").initialize();
    serial.serialWriteSlice("boot: starting ring 3 terminal, IPC server and filesystem server\r\n");
    @import("../../platform/smp.zig").enableUsers(secondaryUsers);
    x86_restore_user(schedule());
}

fn secondaryUsers(_: usize) noreturn {
    smp_dispatch.enter(&kernel.scheduler);
    installGates(smp_dispatch.index());
    @import("../../arch/mod.zig").backend.irq.initializeLocal();
    @import("../../platform/smp.zig").registerIpi();
    @import("timer.zig").initializeLocal();
    x86_restore_user(schedule());
}
