//! Shared on-disk UTF-16 decoding. Reject malformed surrogate pairs and NULs.
const std = @import("std");
pub fn utf16(bytes: []const u8, output: []u8) error{InvalidFilesystem}![]const u8 {
    if (bytes.len % 2 != 0) return error.InvalidFilesystem;
    var position: usize = 0;
    var length: usize = 0;
    while (position < bytes.len) {
        const first = std.mem.readInt(u16, bytes[position..][0..2], .little);
        position += 2;
        var code: u21 = first;
        if (first >= 0xd800 and first <= 0xdbff) {
            if (position == bytes.len) return error.InvalidFilesystem;
            const second = std.mem.readInt(u16, bytes[position..][0..2], .little);
            position += 2;
            if (second < 0xdc00 or second > 0xdfff) return error.InvalidFilesystem;
            code = 0x10000 + (@as(u21, first - 0xd800) << 10) + second - 0xdc00;
        } else if (first >= 0xdc00 and first <= 0xdfff) return error.InvalidFilesystem;
        if (code == 0 or code == '/' or code == '\\') return error.InvalidFilesystem;
        var encoded: [4]u8 = undefined;
        const count = std.unicode.utf8Encode(code, &encoded) catch return error.InvalidFilesystem;
        if (count > output.len - length) return error.InvalidFilesystem;
        @memcpy(output[length..][0..count], encoded[0..count]);
        length += count;
    }
    return output[0..length];
}

test "UTF-16 filenames preserve supplementary characters and reject broken pairs" {
    var output: [32]u8 = undefined;
    try std.testing.expectEqualStrings("中😀", try utf16(&.{ 0x2d, 0x4e, 0x3d, 0xd8, 0, 0xde }, &output));
    try std.testing.expectError(error.InvalidFilesystem, utf16(&.{ 0x3d, 0xd8 }, &output));
    try std.testing.expectError(error.InvalidFilesystem, utf16(&.{ 0, 0xde }, &output));
    try std.testing.expectError(error.InvalidFilesystem, utf16(&.{ 0x3d, 0xd8, 65, 0 }, &output));
    try std.testing.expectError(error.InvalidFilesystem, utf16(&.{ 0, 0 }, &output));
}
