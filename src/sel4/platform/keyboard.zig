//! US keyboard layout for Linux/virtio key codes (not character codes).
//! PS/2 adapters translate their scan codes before entering this decoder.
pub const Decoder = struct {
    left_shift: bool = false,
    right_shift: bool = false,
    left_control: bool = false,
    right_control: bool = false,
    caps: bool = false,

    pub fn feed(self: *Decoder, code: u16, value: u32) ?u8 {
        if (value > 2) return null;
        const down = value != 0;
        switch (code) {
            29 => {
                self.left_control = down;
                return null;
            },
            97 => {
                self.right_control = down;
                return null;
            },
            42 => {
                self.left_shift = down;
                return null;
            },
            54 => {
                self.right_shift = down;
                return null;
            },
            58 => {
                if (value == 1) self.caps = !self.caps;
                return null;
            },
            96 => return if (down) '\r' else null,
            else => {},
        }
        if (!down) return null;
        const normal = "\x00\x1b1234567890-=\x08\tqwertyuiop[]\r\x00asdfghjkl;'`\x00\\zxcvbnm,./\x00*\x00 ";
        const shifted = "\x00\x1b!@#$%^&*()_+\x08\tQWERTYUIOP{}\r\x00ASDFGHJKL:\"~\x00|ZXCVBNM<>?\x00*\x00 ";
        if (code >= normal.len or normal[code] == 0) return null;
        const plain = normal[code];
        if ((self.left_control or self.right_control) and plain >= 'a' and plain <= 'z') return plain - 'a' + 1;
        const shift = self.left_shift or self.right_shift;
        return if (shift != (self.caps and plain >= 'a' and plain <= 'z')) shifted[code] else plain;
    }
};

test "key events retain independent modifiers, ignore release and preserve repeat" {
    const std = @import("std");
    var d: Decoder = .{};
    try std.testing.expectEqual(@as(?u8, 'a'), d.feed(30, 1));
    try std.testing.expectEqual(@as(?u8, null), d.feed(30, 0));
    _ = d.feed(42, 1);
    _ = d.feed(54, 1);
    _ = d.feed(42, 0);
    try std.testing.expectEqual(@as(?u8, 'A'), d.feed(30, 2));
    _ = d.feed(54, 0);
    _ = d.feed(58, 1);
    _ = d.feed(58, 2);
    try std.testing.expectEqual(@as(?u8, 'A'), d.feed(30, 1));
    _ = d.feed(42, 1);
    try std.testing.expectEqual(@as(?u8, 'a'), d.feed(30, 1));
    _ = d.feed(29, 1);
    _ = d.feed(97, 1);
    _ = d.feed(29, 0);
    try std.testing.expectEqual(@as(?u8, 3), d.feed(46, 1));
    try std.testing.expectEqual(@as(?u8, null), d.feed(0xffff, 1));
    try std.testing.expectEqual(@as(?u8, null), d.feed(30, 3));
}
