//! Validated, sorted Unicode glyph atlas generated from the installed Sarasa font.
const std = @import("std");
pub const Font = struct {
    records: []const u8,
    pub fn parse(bytes: []const u8) !Font {
        if (bytes.len < 16 or !std.mem.eql(u8, bytes[0..8], "ZGUF\x01\x00\x10\x10")) return error.InvalidUnicodeFont;
        const count = std.mem.readInt(u32, bytes[8..12], .little);
        if (count > 100000 or bytes.len != 16 + @as(usize, count) * 40 or std.mem.readInt(u32, bytes[12..16], .little) != 40) return error.InvalidUnicodeFont;
        var previous: u32 = 0;
        for (0..count) |index| {
            const record = bytes[16 + index * 40 ..][0..40];
            const code = std.mem.readInt(u32, record[0..4], .little);
            if (code > 0x10ffff or (code >= 0xd800 and code <= 0xdfff) or (index > 0 and code <= previous) or record[4] > 2) return error.InvalidUnicodeFont;
            previous = code;
        }
        return .{ .records = bytes[16..] };
    }
    pub fn lookup(self: Font, code: u21) ?[]const u8 {
        var low: usize = 0;
        var high = self.records.len / 40;
        while (low < high) {
            const mid = low + (high - low) / 2;
            const record = self.records[mid * 40 ..][0..40];
            const candidate = std.mem.readInt(u32, record[0..4], .little);
            if (candidate == code) return record[8..40];
            if (candidate < code) low = mid + 1 else high = mid;
        }
        return null;
    }
};
test "Unicode atlas bounds and sorted lookup" {
    var bytes: [96]u8 = @splat(0);
    @memcpy(bytes[0..8], "ZGUF\x01\x00\x10\x10");
    std.mem.writeInt(u32, bytes[8..12], 2, .little);
    std.mem.writeInt(u32, bytes[12..16], 40, .little);
    std.mem.writeInt(u32, bytes[16..20], 0x4e2d, .little);
    std.mem.writeInt(u32, bytes[56..60], 0xfffd, .little);
    const f = try Font.parse(&bytes);
    try std.testing.expect(f.lookup(0x4e2d) != null);
    try std.testing.expect(f.lookup(0x4e2e) == null);
    try std.testing.expectError(error.InvalidUnicodeFont, Font.parse(bytes[0..95]));
    std.mem.writeInt(u32, bytes[56..60], 0x4e2d, .little);
    try std.testing.expectError(error.InvalidUnicodeFont, Font.parse(&bytes));
}
