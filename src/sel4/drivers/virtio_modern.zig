//! Virtio 1.0 split-queue transport: MMIO v2 or firmware-assigned PCI BARs.
//! Architecture modules supply bus access and physical DMA translation.
const std = @import("std");
const arch = @import("../arch/mod.zig");
const bus = arch.backend.virtio;
const io = @import("../platform/io.zig");
const pci = if (bus.pci_mode) bus.pci else struct {};

pub const Device = struct {
    common: usize,
    notify_base: usize = 0,
    notify_length: u32 = 0,
    notify_multiplier: u32 = 0,

    pub fn find(device_id: u16) !Device {
        if (comptime !bus.pci_mode) {
            for (0..bus.mmio_count) |index| {
                const base: usize = @intCast(bus.mmio_start + index * bus.mmio_stride);
                if (io.read(u32, base) != 0x74726976 or io.read(u32, base + 8) != device_id) continue;
                if (io.read(u32, base + 4) != 2) return error.UnsupportedVirtioVersion;
                return .{ .common = base };
            }
        } else {
            for (0..32) |index| {
                const slot: u8 = @intCast(index);
                if (pci.configRead(slot, 0) != ((@as(u32, 0x1040) + device_id) << 16) | 0x1af4) continue;
                if (pci.configRead(slot, 4) & (1 << 20) == 0) return error.MissingPciCapabilities;
                var cap: u8 = @truncate(pci.configRead(slot, 0x34));
                var common: usize = 0;
                var notification_base: usize = 0;
                var notify_length: u32 = 0;
                var multiplier: u32 = 0;
                // Bound traversal even when firmware/device capability links cycle.
                for (0..48) |_| {
                    if (cap == 0) break;
                    if (cap < 0x40 or cap & 3 != 0) return error.InvalidPciCapability;
                    const header = pci.configRead(slot, cap);
                    const next: u8 = @truncate(header >> 8);
                    if (header & 0xff == 9) {
                        if (cap > 0xf0 or (header >> 16) & 0xff < 16) return error.InvalidPciCapability;
                        const kind: u8 = @truncate(header >> 24);
                        if (kind == 1 or kind == 2) {
                            const bar_index: u8 = @truncate(pci.configRead(slot, cap + 4));
                            const offset = pci.configRead(slot, cap + 8);
                            const length = pci.configRead(slot, cap + 12);
                            const address = try regionAddress(slot, bar_index, offset, length);
                            if (kind == 1) {
                                if (length < 56 or address & 3 != 0) return error.InvalidPciCapability;
                                common = address;
                            } else {
                                if (cap > 0xec or (header >> 16) & 0xff < 20) return error.InvalidPciCapability;
                                notification_base = address;
                                notify_length = length;
                                multiplier = pci.configRead(slot, cap + 16);
                            }
                        }
                    }
                    cap = next;
                }
                if (cap != 0 or common == 0 or notification_base == 0) return error.InvalidPciCapability;
                // Enable memory decode and bus mastering; do not acknowledge PCI status bits.
                pci.configWrite(slot, 4, (pci.configRead(slot, 4) & 0xffff) | 6);
                return .{ .common = common, .notify_base = notification_base, .notify_length = notify_length, .notify_multiplier = multiplier };
            }
        }
        return error.NoVirtioInput;
    }

    fn regionAddress(slot: u8, index: u8, offset: u32, length: u32) !usize {
        if (index >= 6 or length == 0) return error.InvalidPciCapability;
        const bar = pci.configRead(slot, 0x10 + index * 4);
        if (bar & 1 != 0) return error.UnsupportedPciBar;
        var base: u64 = bar & 0xfffffff0;
        switch (bar & 6) {
            0 => {},
            4 => {
                if (index == 5) return error.UnsupportedPciBar;
                base |= @as(u64, pci.configRead(slot, 0x14 + index * 4)) << 32;
            },
            else => return error.UnsupportedPciBar,
        }
        if (base == 0) return error.UnassignedPciBar;
        const address = std.math.add(u64, base, offset) catch return error.InvalidPciCapability;
        _ = std.math.add(u64, address, length) catch return error.InvalidPciCapability;
        return arch.backend.framebufferAddress(address);
    }

    fn status(self: Device) u8 {
        return if (bus.pci_mode) io.read(u8, self.common + 20) else @truncate(io.read(u32, self.common + 0x70));
    }
    fn setStatus(self: Device, value: u8) void {
        if (comptime bus.pci_mode) io.write(u8, self.common + 20, value) else io.write(u32, self.common + 0x70, value);
    }
    pub fn negotiate(self: Device) !void {
        self.setStatus(0);
        var reset = false;
        for (0..100000) |_| {
            if (self.status() == 0) {
                reset = true;
                break;
            }
            arch.relax();
        }
        if (!reset) return error.VirtioResetTimeout;
        self.setStatus(3);
        const feature_select: usize = if (bus.pci_mode) 0 else 0x14;
        const features: usize = if (bus.pci_mode) 4 else 0x10;
        const driver_select: usize = if (bus.pci_mode) 8 else 0x24;
        const driver_features: usize = if (bus.pci_mode) 12 else 0x20;
        io.write(u32, self.common + feature_select, 1);
        if (io.read(u32, self.common + features) & 1 == 0) return error.UnsupportedVirtioVersion;
        io.write(u32, self.common + driver_select, 0);
        io.write(u32, self.common + driver_features, 0);
        io.write(u32, self.common + driver_select, 1);
        io.write(u32, self.common + driver_features, 1);
        self.setStatus(11);
        if (self.status() & 8 == 0) return error.VirtioFeatureRejected;
    }

    /// Install a split ring. No indirect descriptors or notification-data feature.
    pub fn setupQueue(self: Device, index: u16, size: u16, desc: usize, avail: usize, used: usize) !usize {
        const selector: usize = if (bus.pci_mode) 22 else 0x30;
        if (comptime bus.pci_mode) io.write(u16, self.common + selector, index) else io.write(u32, self.common + selector, index);
        const maximum = if (bus.pci_mode) io.read(u16, self.common + 24) else io.read(u32, self.common + 0x34);
        if (size == 0 or size & (size - 1) != 0 or maximum < size) return error.UnsupportedQueue;
        if (comptime bus.pci_mode) {
            if (io.read(u16, self.common + 28) != 0) return error.QueueAlreadyActive;
            io.write(u16, self.common + 24, size);
            io.write(u16, self.common + 26, 0xffff);
        } else {
            if (io.read(u32, self.common + 0x44) != 0) return error.QueueAlreadyActive;
            io.write(u32, self.common + 0x38, size);
        }
        const addresses = [_]usize{ desc, avail, used };
        const offsets = if (bus.pci_mode) [_]usize{ 32, 40, 48 } else [_]usize{ 0x80, 0x90, 0xa0 };
        for (addresses, offsets) |address, offset| {
            const physical = bus.physical(address);
            io.write(u32, self.common + offset, @truncate(physical));
            io.write(u32, self.common + offset + 4, @truncate(physical >> 32));
        }
        arch.backend.dmaBarrier();
        if (comptime bus.pci_mode) {
            const offset = @as(u64, io.read(u16, self.common + 30)) * self.notify_multiplier;
            if (offset + 2 > self.notify_length or offset & 1 != 0) return error.InvalidPciCapability;
            io.write(u16, self.common + 28, 1);
            return self.notify_base + @as(usize, @intCast(offset));
        } else {
            io.write(u32, self.common + 0x44, 1);
            return self.common + 0x50;
        }
    }
    pub fn ready(self: Device) !void {
        self.setStatus(15);
        if (self.status() & 0xcf != 15) return error.VirtioDeviceFailed;
    }
    pub fn failed(self: Device) void {
        self.setStatus(self.status() | 0x80);
    }
    pub fn notify(address: usize, index: u16) void {
        if (comptime bus.pci_mode) io.write(u16, address, index) else io.write(u32, address, index);
    }
};
