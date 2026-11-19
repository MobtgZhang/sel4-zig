//! Canonical absolute paths for mounted disk filesystems; UTF-8 names are allowed.
const std = @import("std");
pub fn validate(path: []const u8) error{InvalidPath}!void {
    if (path.len == 0 or path.len > 1024 or path[0] != '/' or !std.unicode.utf8ValidateSlice(path)) return error.InvalidPath;
    if (path.len == 1) return;
    var parts = std.mem.splitScalar(u8, path[1..], '/');
    while (parts.next()) |part| {
        if (part.len == 0 or part.len > 255 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return error.InvalidPath;
        for (part) |byte| if (byte < 32 or byte == 127 or byte == '\\') return error.InvalidPath;
    }
}
