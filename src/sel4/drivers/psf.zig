//! Strict PSF2 bitmap parser; the console supports 256 eight-by-sixteen cells.
const std = @import("std");
pub const Font = struct {
    rows: []const u8,
    pub fn parse(bytes: []const u8) !Font {
        if (bytes.len != 32 + 256 * 16) return error.InvalidFont;
        const expected = [_]u32{ 0x864ab572, 0, 32, 0, 256, 16, 16, 8 };
        for (expected, 0..) |word, i| if (std.mem.readInt(u32, bytes[i * 4 ..][0..4], .little) != word) return error.InvalidFont;
        return .{ .rows = bytes[32..] };
    }
    pub fn row(self: Font, byte: u8, y: usize) u8 {
        return self.rows[@as(usize, byte) * 16 + y];
    }
};
test "PSF rejects geometry and truncation" {
    var bytes: [4128]u8 = @splat(0);
    const header = [_]u32{ 0x864ab572, 0, 32, 0, 256, 16, 16, 8 };
    for (header, 0..) |word, i| std.mem.writeInt(u32, bytes[i * 4 ..][0..4], word, .little);
    _ = try Font.parse(&bytes);
    try std.testing.expectError(error.InvalidFont, Font.parse(bytes[0..100]));
    bytes[28] = 9;
    try std.testing.expectError(error.InvalidFont, Font.parse(&bytes));
}
