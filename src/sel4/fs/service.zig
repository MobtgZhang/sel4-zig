//! Privileged bootstrap filesystem service. This is not an upstream seL4 ABI.
const system = @import("system.zig");
const console = @import("../platform/console.zig");
pub fn run(command: u64, argument: []const u8) bool {
    execute(command, argument) catch |err| {
        console.serialWriteSlice("system: ");
        console.serialWriteSlice(@errorName(err));
        console.serialWriteSlice("\r\n");
        return false;
    };
    return true;
}
fn execute(command: u64, argument: []const u8) !void {
    switch (command) {
        0, 1 => try @import("commands.zig").execute(&system.root, command, argument, Writer{}),
        2 => {
            if (argument.len == 0) {
                console.serialWriteSlice("Fonts: plex (default), iosevka, sarasa\r\n");
                return;
            }
            try console.selectFont(argument);
            console.serialWriteSlice("System font: ");
            console.serialWriteSlice(argument);
            console.serialWriteSlice("\r\n");
        },
        else => return error.InvalidOperation,
    }
}

const Writer = struct {
    pub fn write(_: Writer, bytes: []const u8) !void {
        console.serialWriteSlice(bytes);
    }
};
