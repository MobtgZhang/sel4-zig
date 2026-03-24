//! 参考 ZirconOS：comptime UTF-16 字面量 + 按位十进制，避免大栈缓冲。
const std = @import("std");
const uefi = std.os.uefi;
const unicode = std.unicode;

pub fn puts(out: *uefi.protocol.SimpleTextOutput, comptime s: []const u8) void {
    _ = out.outputString(unicode.utf8ToUtf16LeStringLiteral(s)) catch {};
}

pub fn printU64(out: *uefi.protocol.SimpleTextOutput, value: u64) void {
    if (value >= 10)
        printU64(out, value / 10);
    const digit: u8 = @truncate('0' + (value % 10));
    var buf: [1:0]u16 = .{@as(u16, digit)};
    _ = out.outputString(&buf) catch {};
}
