//! Firmware-independent 32-bit linear framebuffer and bounded text renderer.
const std = @import("std");
const font = @import("font8x8.zig").glyphs;

pub const Descriptor = extern struct {
    address: u64 = 0,
    byte_size: u64 = 0,
    width: u32 = 0,
    height: u32 = 0,
    stride: u32 = 0,
    red_mask: u32 = 0,
    green_mask: u32 = 0,
    blue_mask: u32 = 0,

    pub fn validate(self: Descriptor) !void {
        if (self.address == 0 or self.address % 4 != 0 or self.width < 80 or self.height < 32 or
            self.width > 8192 or self.height > 8192 or self.stride < self.width or self.stride > 16384)
            return error.InvalidFramebuffer;
        const required = @as(u64, self.stride) * self.height * 4;
        if (required > self.byte_size or self.byte_size > 256 * 1024 * 1024 or
            self.address > std.math.maxInt(u64) - self.byte_size) return error.InvalidFramebuffer;
        if (self.red_mask == 0 or self.green_mask == 0 or self.blue_mask == 0 or
            self.red_mask & self.green_mask != 0 or self.red_mask & self.blue_mask != 0 or self.green_mask & self.blue_mask != 0)
            return error.InvalidFramebuffer;
        for ([_]u32{ self.red_mask, self.green_mask, self.blue_mask }) |mask| {
            const shifted = mask >> @as(u5, @intCast(@ctz(mask)));
            if (shifted & (shifted +% 1) != 0) return error.InvalidFramebuffer;
        }
    }
    fn channel(value: u8, mask: u32) u32 {
        const shift: u5 = @intCast(@ctz(mask));
        const maximum = mask >> shift;
        return @as(u32, @intCast((@as(u64, value) * maximum + 127) / 255)) << shift;
    }
    pub fn color(self: Descriptor, red: u8, green: u8, blue: u8) u32 {
        return channel(red, self.red_mask) | channel(green, self.green_mask) | channel(blue, self.blue_mask);
    }
};

pub const Terminal = struct {
    descriptor: Descriptor,
    pixels: [*]volatile u32,
    bitmap: ?@import("psf.zig").Font = null,
    unicode_font: ?@import("unicode_font.zig").Font = null,
    decoder: @import("terminal").text.Decoder = .{},
    previous_column: u32 = 0,
    previous_row: u32 = 0,
    previous_width: u2 = 1,
    has_previous: bool = false,
    column: u32 = 0,
    row: u32 = 0,
    escape: enum { none, start, csi } = .none,
    escape_clear: bool = false,
    foreground: u32,
    background: u32,

    pub fn init(descriptor: Descriptor) !Terminal {
        try descriptor.validate();
        var terminal = Terminal{
            .descriptor = descriptor,
            .pixels = @ptrFromInt(descriptor.address),
            .foreground = descriptor.color(224, 232, 240),
            .background = descriptor.color(16, 24, 36),
        };
        terminal.clear();
        return terminal;
    }
    pub fn clear(self: *Terminal) void {
        for (0..@as(usize, self.descriptor.stride) * self.descriptor.height) |i| self.pixels[i] = self.background;
        self.column = 0;
        self.row = 0;
        self.has_previous = false;
        self.decoder = .{};
    }
    fn glyph(self: *Terminal, codepoint: u21) void {
        const width = @import("terminal").text.cellWidth(codepoint);
        const columns = self.descriptor.width / 8;
        if (width > 0 and self.column + width > columns) self.newline();
        if (width == 0 and !self.has_previous) return;
        const column = if (width == 0) self.previous_column else self.column;
        const row = if (width == 0) self.previous_row else self.row;
        const cells: usize = if (width == 0) self.previous_width else width;
        const extended = if (self.unicode_font) |atlas| atlas.lookup(codepoint) else null;
        const fallback: u8 = if (codepoint < 128) @intCast(codepoint) else '?';
        const shape = font[fallback];
        for (0..16) |y| for (0..cells * 8) |x| {
            if (@as(usize, column) * 8 + x >= self.descriptor.width) continue;
            const offset = (@as(usize, row) * 16 + y) * self.descriptor.stride + @as(usize, column) * 8 + x;
            const lit = if (codepoint >= 128 and extended != null)
                extended.?[y * 2 + x / 8] & (@as(u8, 0x80) >> @as(u3, @intCast(x % 8))) != 0
            else if (x >= 8) false else if (self.bitmap) |bitmap|
                bitmap.row(fallback, y) & (@as(u8, 0x80) >> @as(u3, @intCast(x))) != 0
            else
                shape[y / 2] & (@as(u8, 1) << @as(u3, @intCast(x))) != 0;
            if (lit or width != 0) self.pixels[offset] = if (lit) self.foreground else self.background;
        };
        if (width != 0) {
            self.previous_column = self.column;
            self.previous_row = self.row;
            self.previous_width = width;
            self.has_previous = true;
        }
        // Defer automatic wrapping so backspace can erase the rightmost cell.
        self.column += width;
    }
    fn newline(self: *Terminal) void {
        self.column = 0;
        self.row += 1;
        const rows = self.descriptor.height / 16;
        if (self.row < rows) return;
        const stride: usize = self.descriptor.stride;
        const visible = @as(usize, rows) * 16 * stride;
        const removed = 16 * stride;
        for (0..visible - removed) |i| self.pixels[i] = self.pixels[i + removed];
        for (visible - removed..visible) |i| self.pixels[i] = self.background;
        self.row = rows - 1;
        if (self.has_previous) {
            if (self.previous_row == 0) self.has_previous = false else self.previous_row -= 1;
        }
    }
    pub fn write(self: *Terminal, bytes: []const u8) void {
        for (bytes) |byte| {
            if (self.escape != .none) {
                switch (self.escape) {
                    .start => {
                        self.escape = if (byte == '[') .csi else .none;
                        self.escape_clear = false;
                    },
                    .csi => {
                        if (byte == '2') self.escape_clear = true;
                        if (byte >= 0x40 and byte <= 0x7e) {
                            if (byte == 'J' and self.escape_clear) self.clear();
                            if (byte == 'H') {
                                self.row = 0;
                                self.column = 0;
                            }
                            self.escape = .none;
                        }
                    },
                    .none => unreachable,
                }
                continue;
            }
            const decoded = self.decoder.feed(byte);
            for (decoded.codes[0..decoded.count]) |codepoint| switch (codepoint) {
                0x1b => self.escape = .start,
                '\r' => self.column = 0,
                '\n' => self.newline(),
                '\x08' => {
                    if (self.column > 0) self.column -= 1 else if (self.row > 0) {
                        self.row -= 1;
                        self.column = self.descriptor.width / 8 - 1;
                    }
                    self.has_previous = false;
                },
                '\t' => {
                    for (0..8 - self.column % 8) |_| self.glyph(' ');
                },
                0...7, 11...12, 14...26, 28...31, 0x7f...0x9f => {},
                else => self.glyph(codepoint),
            };
        }
    }
};

test "framebuffer bounds, channel order, scrolling and escape handling" {
    var pixels: [80 * 48 + 2]u32 = @splat(0xdeadbeef);
    const descriptor: Descriptor = .{ .address = @intFromPtr(&pixels[1]), .byte_size = 80 * 48 * 4, .width = 80, .height = 48, .stride = 80, .red_mask = 0xff0000, .green_mask = 0xff00, .blue_mask = 0xff };
    try std.testing.expectEqual(@as(u32, 0x123456), descriptor.color(0x12, 0x34, 0x56));
    var terminal = try Terminal.init(descriptor);
    terminal.write("first\nsecond\nthird\nfourth\x1b[2J\x1b[Hready");
    try std.testing.expectEqual(@as(u32, 0), terminal.row);
    try std.testing.expectEqual(@as(u32, 5), terminal.column);
    try std.testing.expectEqual(@as(u32, 0xdeadbeef), pixels[0]);
    try std.testing.expectEqual(@as(u32, 0xdeadbeef), pixels[pixels.len - 1]);
    var bad = descriptor;
    bad.byte_size -= 1;
    try std.testing.expectError(error.InvalidFramebuffer, Terminal.init(bad));
    bad = descriptor;
    bad.green_mask = bad.red_mask;
    try std.testing.expectError(error.InvalidFramebuffer, bad.validate());
}

test "right-margin backspace and combining glyphs preserve cursor and bounds" {
    var pixels: [80 * 48 + 2]u32 = @splat(0xdeadbeef);
    const descriptor: Descriptor = .{ .address = @intFromPtr(&pixels[1]), .byte_size = 80 * 48 * 4, .width = 80, .height = 48, .stride = 80, .red_mask = 0xff0000, .green_mask = 0xff00, .blue_mask = 0xff };
    var terminal = try Terminal.init(descriptor);
    terminal.write("12345678中");
    try std.testing.expectEqual(@as(u32, 10), terminal.column);
    try std.testing.expectEqual(@as(u32, 0), terminal.row);
    terminal.write("\x08 \x08\x08 \x08");
    try std.testing.expectEqual(@as(u32, 8), terminal.column);
    terminal.write("中\xcc\x81");
    try std.testing.expectEqual(@as(u32, 10), terminal.column);
    try std.testing.expectEqual(@as(u32, 0), terminal.row);
    terminal.write("x\x08 \x08\x08");
    try std.testing.expectEqual(@as(u32, 9), terminal.column);
    try std.testing.expectEqual(@as(u32, 0), terminal.row);
    try std.testing.expectEqual(@as(u32, 0xdeadbeef), pixels[0]);
    try std.testing.expectEqual(@as(u32, 0xdeadbeef), pixels[pixels.len - 1]);
}
