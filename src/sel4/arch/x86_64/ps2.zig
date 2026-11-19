//! Polled i8042 keyboard, translated set-1 scancodes and US key layout.
const io = @import("../../platform/io.zig");
pub const name = "PS/2";
pub fn initialize() !void {
    if (!init()) return error.KeyboardUnavailable;
}
pub const Decoder = struct {
    keys: @import("../../platform/keyboard.zig").Decoder = .{},
    extended: bool = false,
    pause_remaining: u3 = 0,
    pub fn feed(self: *Decoder, scan: u8) ?u8 {
        if (self.pause_remaining > 0) {
            self.pause_remaining -= 1;
            return null;
        }
        if (scan == 0xe1) {
            self.pause_remaining = 5;
            return null;
        }
        if (scan == 0xe0) {
            self.extended = true;
            return null;
        }
        const extended = self.extended;
        self.extended = false;
        const key = scan & 0x7f;
        const down = scan & 0x80 == 0;
        const code: u16 = if (extended) switch (key) {
            0x1d => 97,
            0x1c => 96,
            else => return null,
        } else key;
        return self.keys.feed(code, if (down) 1 else 0);
    }
};
var decoder: Decoder = .{};
var enabled = false;
fn waitWrite() bool {
    for (0..100000) |_| {
        if (io.in8(0x64) & 2 == 0) return true;
    }
    return false;
}
fn command(value: u8) bool {
    if (!waitWrite()) return false;
    io.out8(0x64, value);
    return true;
}
fn data(value: u8) bool {
    if (!waitWrite()) return false;
    io.out8(0x60, value);
    return true;
}
pub fn init() bool {
    enabled = false;
    decoder = .{};
    if (!command(0xad) or !command(0xa7)) return false;
    for (0..256) |_| {
        if (io.in8(0x64) & 1 == 0) break;
        _ = io.in8(0x60);
    }
    if (!command(0x20)) return false;
    var config: ?u8 = null;
    for (0..100000) |_| {
        if (io.in8(0x64) & 1 != 0) {
            config = io.in8(0x60);
            break;
        }
    }
    // Translate to set 1; mask interrupts because this bootstrap console polls.
    const value = ((config orelse return false) | 0x40) & ~@as(u8, 0x13);
    if (!command(0x60) or !data(value) or !command(0xae) or !data(0xf4)) return false;
    for (0..100000) |_| {
        if (io.in8(0x64) & 1 != 0) {
            if (io.in8(0x60) != 0xfa) return false;
            enabled = true;
            return true;
        }
    }
    return false;
}
pub fn poll() ?u8 {
    if (!enabled) return null;
    const status = io.in8(0x64);
    if (status & 1 == 0) return null;
    const scan = io.in8(0x60);
    if (status & 0xe0 != 0) return null;
    return decoder.feed(scan);
}
test "keyboard modifiers, releases, controls and extended keys" {
    const std = @import("std");
    var decoder_test: Decoder = .{};
    try std.testing.expectEqual(@as(?u8, 'a'), decoder_test.feed(0x1e));
    _ = decoder_test.feed(0x2a);
    try std.testing.expectEqual(@as(?u8, 'A'), decoder_test.feed(0x1e));
    _ = decoder_test.feed(0xaa);
    _ = decoder_test.feed(0x1d);
    try std.testing.expectEqual(@as(?u8, 3), decoder_test.feed(0x2e));
    _ = decoder_test.feed(0x9d);
    _ = decoder_test.feed(0xe0);
    try std.testing.expectEqual(@as(?u8, null), decoder_test.feed(0x48));
    try std.testing.expectEqual(@as(?u8, 'b'), decoder_test.feed(0x30));
}
