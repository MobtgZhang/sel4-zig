//! Polled virtio keyboard with kernel-owned split rings and event buffers.
//! Device DMA never targets userspace. Bad completions permanently stop polling.
const modern = @import("virtio_modern.zig");
const arch = @import("../arch/mod.zig");
const keyboard = @import("../platform/keyboard.zig");
pub const name = "virtio";
const queue_size = 64;
const Descriptor = extern struct { address: u64, length: u32, flags: u16, next: u16 = 0 };
const Event = extern struct { kind: u16, code: u16, value: u32 };
const Available = extern struct { flags: u16 = 1, index: u16 = 0, ring: [queue_size]u16 = @splat(0), unused_event: u16 = 0 };
const Used = extern struct {
    flags: u16 = 0,
    index: u16 = 0,
    ring: [queue_size]extern struct { id: u32, length: u32 } = @splat(.{ .id = 0, .length = 0 }),
    unused_event: u16 = 0,
};
const Queue = struct {
    descriptors: [queue_size]Descriptor align(16) = undefined,
    available: Available align(2) = .{},
    used: Used align(4) = .{},
};
var events_queue: Queue = .{};
var status_queue: Queue = .{};
var events: [queue_size]Event align(8) = undefined;
var decoder: keyboard.Decoder = .{};
var notification: usize = 0;
var consumed: u16 = 0;
var published: u16 = 0;
var enabled = false;
var attempted = false;
var device: ?modern.Device = null;
var lock: @import("../platform/sync.zig").SpinLock = .{};

pub fn initialize() !void {
    lock.lock();
    defer lock.unlock();
    if (attempted) return error.AlreadyInitialized;
    attempted = true;
    const found = try modern.Device.find(18);
    device = found;
    errdefer found.failed();
    try found.negotiate();
    events_queue = .{};
    status_queue = .{};
    decoder = .{};
    for (&events_queue.descriptors, 0..) |*descriptor, index| {
        descriptor.* = .{ .address = arch.backend.virtio.physical(@intFromPtr(&events[index])), .length = @sizeOf(Event), .flags = 2 };
        events_queue.available.ring[index] = @intCast(index);
    }
    events_queue.available.index = queue_size;
    published = queue_size;
    consumed = 0;
    notification = try found.setupQueue(0, queue_size, @intFromPtr(&events_queue.descriptors), @intFromPtr(&events_queue.available), @intFromPtr(&events_queue.used));
    _ = try found.setupQueue(1, queue_size, @intFromPtr(&status_queue.descriptors), @intFromPtr(&status_queue.available), @intFromPtr(&status_queue.used));
    try found.ready();
    enabled = true;
    modern.Device.notify(notification, 0);
}

pub fn poll() ?u8 {
    lock.lock();
    defer lock.unlock();
    if (!enabled) return null;
    // Bound work per poll so serial input cannot starve under a device flood.
    for (0..queue_size) |_| {
        const produced = @as(*volatile Used, &events_queue.used).index;
        if (produced == consumed) return null;
        arch.backend.dmaBarrier();
        const item = @as(*volatile Used, &events_queue.used).ring[consumed % queue_size];
        if (produced -% consumed > queue_size or item.id >= queue_size or item.length != @sizeOf(Event)) {
            enabled = false;
            if (device) |found| found.failed();
            return null;
        }
        const event = @as(*volatile Event, &events[item.id]).*;
        consumed +%= 1;
        @as(*volatile Available, &events_queue.available).ring[published % queue_size] = @intCast(item.id);
        arch.backend.dmaBarrier();
        published +%= 1;
        @as(*volatile Available, &events_queue.available).index = published;
        arch.backend.dmaBarrier();
        modern.Device.notify(notification, 0);
        if (event.kind == 1) {
            if (decoder.feed(event.code, event.value)) |byte| return byte;
        }
    }
    return null;
}
