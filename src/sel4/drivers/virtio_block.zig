//! Serialized, polling virtio block transport over legacy PCI or modern MMIO.
//! One request owns all DMA storage until completion; timeout poisons the queue.
const std = @import("std");
const arch = @import("../arch/mod.zig");
const io = @import("../platform/io.zig");
const Deadline = @import("../platform/clock.zig").Deadline;
const transport = arch.backend.virtio;
const pci_mode = transport.pci_mode;
const pci = if (pci_mode) transport.pci else struct {};
const physical = transport.physical;

const RequestKind = enum(u32) { read = 0, write = 1, flush = 4 };
const Descriptor = extern struct { address: u64, length: u32, flags: u16, next: u16 };
const Header = extern struct { kind: RequestKind = .read, reserved: u32 = 0, sector: u64 = 0 };
const descriptor_next = 1;
const descriptor_device_writes = 2;
const feature_flush = 1 << 9;
const request_timeout_ms = 5_000;

var queue: [12288]u8 align(4096) = @splat(0);
var header: Header align(16) = .{};
var data: [512]u8 align(16) = undefined;
var request_status: u8 = 0xff;
var base: u64 = 0;
var queue_size: u16 = 0;
var available: u16 = 0;
var consumed: u16 = 0;
var flush_supported = false;
var poisoned = false;
var device_lock: @import("../platform/sync.zig").SpinLock = .{};
pub var sectors: u64 = 0;

fn mmioRead(comptime T: type, offset: u64) T {
    return io.read(T, @intCast(base + offset));
}
fn mmioWrite(comptime T: type, offset: u64, value: T) void {
    io.write(T, @intCast(base + offset), value);
}
fn mmioAddress(offset: u64, address: u64) void {
    mmioWrite(u32, offset, @truncate(address));
    mmioWrite(u32, offset + 4, @truncate(address >> 32));
}
fn validateQueueSize() !void {
    if (queue_size < 4 or queue_size > 256 or !std.math.isPowerOfTwo(queue_size)) return error.UnsupportedQueue;
}
fn availableOffset() usize {
    return 16 * @as(usize, queue_size);
}
fn usedOffset() usize {
    // Legacy transport fixes the used ring to the next page after the avail ring.
    return if (pci_mode) std.mem.alignForward(usize, availableOffset() + 6 + 2 * @as(usize, queue_size), 4096) else 8192;
}
fn ringWord(offset: usize) *volatile u16 {
    return @ptrCast(@alignCast(&queue[offset]));
}

fn initializePci() !void {
    for (0..32) |index| {
        const slot: u8 = @intCast(index);
        if (pci.configRead(slot, 0) != 0x10011af4) continue;
        var bar = pci.configRead(slot, 0x10);
        if (bar & 1 == 0) continue;
        if (bar & 0xfffffffc == 0) {
            bar = 0xc001;
            pci.configWrite(slot, 0x10, bar);
        }
        base = bar & 0xfffffffc;
        pci.configWrite(slot, 4, (pci.configRead(slot, 4) & 0xffff) | 5);
        break;
    }
    if (base == 0) return error.NoPersistentDisk;
    pci.write(u8, base + 18, 0);
    const reset = Deadline.afterMilliseconds(1_000);
    while (pci.read(u8, base + 18) != 0) {
        if (reset.expired()) return error.DeviceResetTimeout;
        arch.relax();
    }
    pci.write(u8, base + 18, 3); // ACKNOWLEDGE | DRIVER.
    flush_supported = pci.read(u32, base) & feature_flush != 0;
    pci.write(u32, base + 4, if (flush_supported) feature_flush else 0);
    pci.write(u16, base + 14, 0);
    queue_size = pci.read(u16, base + 12);
    try validateQueueSize();
    arch.backend.dmaBarrier();
    pci.write(u32, base + 8, @intCast(physical(@intFromPtr(&queue)) >> 12));
    pci.write(u8, base + 18, 7); // DRIVER_OK; legacy transport has no FEATURES_OK.
    sectors = @as(u64, pci.read(u32, base + 20)) | (@as(u64, pci.read(u32, base + 24)) << 32);
}

fn initializeMmio() !void {
    for (0..transport.mmio_count) |index| {
        base = transport.mmio_start + index * transport.mmio_stride;
        if (mmioRead(u32, 0) == 0x74726976 and mmioRead(u32, 8) == 2) break;
        base = 0;
    }
    if (base == 0) return error.NoPersistentDisk;
    if (mmioRead(u32, 4) != 2) return error.UnsupportedVirtioVersion;
    mmioWrite(u32, 0x70, 0);
    const reset = Deadline.afterMilliseconds(1_000);
    while (mmioRead(u32, 0x70) != 0) {
        if (reset.expired()) return error.DeviceResetTimeout;
        arch.relax();
    }
    mmioWrite(u32, 0x70, 3);
    mmioWrite(u32, 0x14, 0);
    flush_supported = mmioRead(u32, 0x10) & feature_flush != 0;
    mmioWrite(u32, 0x14, 1);
    if (mmioRead(u32, 0x10) & 1 == 0) return error.UnsupportedVirtioVersion;
    mmioWrite(u32, 0x24, 0);
    mmioWrite(u32, 0x20, if (flush_supported) feature_flush else 0);
    mmioWrite(u32, 0x24, 1);
    mmioWrite(u32, 0x20, 1); // VIRTIO_F_VERSION_1 is mandatory for modern transport.
    mmioWrite(u32, 0x70, 11);
    if (mmioRead(u32, 0x70) & 8 == 0) return error.VirtioFeatureRejected;
    mmioWrite(u32, 0x30, 0);
    queue_size = @intCast(@min(256, mmioRead(u32, 0x34)));
    try validateQueueSize();
    mmioWrite(u32, 0x38, queue_size);
    const address = physical(@intFromPtr(&queue));
    mmioAddress(0x80, address);
    mmioAddress(0x90, address + availableOffset());
    mmioAddress(0xa0, address + usedOffset());
    arch.backend.dmaBarrier();
    mmioWrite(u32, 0x44, 1);
    mmioWrite(u32, 0x70, 15);
    sectors = mmioRead(u64, 0x100);
}

pub fn init() !void {
    device_lock.lock();
    defer device_lock.unlock();
    // Initialization is boot-only: resetting an active device needs DMA quiescence.
    base = 0;
    queue_size = 0;
    sectors = 0;
    poisoned = false;
    flush_supported = false;
    available = 0;
    consumed = 0;
    @memset(&queue, 0);
    if (comptime pci_mode) try initializePci() else try initializeMmio();
}

fn publish(kind: RequestKind, sector: u64, buffer: *const [512]u8) void {
    header = .{ .kind = kind, .sector = sector };
    request_status = 0xff;
    if (kind == .write) data = buffer.*;
    const descriptors: [*]Descriptor = @ptrCast(@alignCast(&queue));
    descriptors[0] = .{ .address = physical(@intFromPtr(&header)), .length = 16, .flags = descriptor_next, .next = if (kind == .flush) 2 else 1 };
    descriptors[1] = .{ .address = physical(@intFromPtr(&data)), .length = 512, .flags = descriptor_next | (if (kind == .read) @as(u16, descriptor_device_writes) else 0), .next = 2 };
    descriptors[2] = .{ .address = physical(@intFromPtr(&request_status)), .length = 1, .flags = descriptor_device_writes, .next = 0 };
    ringWord(availableOffset() + 4 + 2 * (available % queue_size)).* = 0;
    // The device must observe the complete chain before the new avail index.
    arch.backend.dmaBarrier();
    available +%= 1;
    ringWord(availableOffset() + 2).* = available;
    arch.backend.dmaBarrier();
    if (comptime pci_mode) pci.write(u16, base + 16, 0) else mmioWrite(u32, 0x50, 0);
}

fn awaitCompletion() !void {
    const deadline = Deadline.afterMilliseconds(request_timeout_ms);
    const used_index = ringWord(usedOffset() + 2);
    while (used_index.* == consumed) {
        // Loop counts depend on the CPU and emulator. Only counter time defines
        // the device's deadline, including when the host delays a disk write.
        if (deadline.expired()) {
            poisoned = true;
            return error.DiskTimeout;
        }
        arch.relax();
    }
    arch.backend.dmaBarrier();
    const element = usedOffset() + 4 + 8 * @as(usize, consumed % queue_size);
    const head: *volatile u32 = @ptrCast(@alignCast(&queue[element]));
    if (used_index.* != consumed +% 1 or head.* != 0) {
        poisoned = true;
        return error.InvalidDeviceCompletion;
    }
    consumed +%= 1;
    // Polling still acknowledges the transport ISR to avoid a stuck IRQ source.
    if (comptime pci_mode) {
        _ = pci.read(u8, base + 19);
    } else {
        mmioWrite(u32, 0x64, mmioRead(u32, 0x60));
    }
    if (@as(*volatile u8, &request_status).* != 0) return error.DiskRequestFailed;
}

fn request(kind: RequestKind, sector: u64, buffer: *[512]u8) !void {
    device_lock.lock();
    defer device_lock.unlock();
    // A timed-out DMA chain may still be device-owned. Never reuse its buffers.
    if (poisoned) return error.DeviceNeedsReset;
    if (base == 0 or queue_size == 0) return error.NoPersistentDisk;
    if (kind != .flush and sector >= sectors) return error.SectorOutOfRange;
    publish(kind, sector, buffer);
    try awaitCompletion();
    if (kind == .read) buffer.* = data;
}
pub fn read(sector: u64, buffer: *[512]u8) !void {
    try request(.read, sector, buffer);
}
pub fn write(sector: u64, buffer: *const [512]u8) !void {
    var copy = buffer.*;
    try request(.write, sector, &copy);
}
pub fn flush() !void {
    if (!flush_supported) return error.FlushUnsupported;
    var dummy: [512]u8 = undefined;
    try request(.flush, 0, &dummy);
}
