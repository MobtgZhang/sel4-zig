//! Filesystem command formatting with no device, firmware or kernel dependencies.
const std = @import("std");
pub fn execute(fs: anytype, command: u64, argument: []const u8, writer: anytype) !void {
    switch (command) {
        0 => {
            const path = if (argument.len == 0) "/" else argument;
            try fs.list(path, writer);
        },
        1 => {
            const size = try fs.fileSize(argument);
            if (size > 16 * 1024) return error.FileTooLargeForConsole;
            var buffer: [16 * 1024]u8 = undefined;
            const count = try fs.readAt(argument, 0, buffer[0..@intCast(size)]);
            if (count != size) return error.InvalidFilesystem;
            const data = buffer[0..count];
            if (!std.unicode.utf8ValidateSlice(data)) return error.BinaryFile;
            for (data) |b| if ((b < 32 and b != '\n' and b != '\r' and b != '\t') or b == 127) return error.BinaryFile;
            for (data) |b| {
                if (b == '\n') try writer.write("\r");
                try writer.write(&.{b});
            }
            if (!std.mem.endsWith(u8, data, "\n")) try writer.write("\r\n");
        },
        else => return error.InvalidOperation,
    }
}
