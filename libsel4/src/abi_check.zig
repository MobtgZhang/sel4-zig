//! Compile the inline syscall assembly without executing privileged ABI calls.
const bindings = @import("libsel4");
export fn compileSend(destination: usize, info: usize, a: usize, b: usize, c: usize, d: usize) void {
    bindings.seL4_SendWithMRs(destination, .{ .words = .{info} }, a, b, c, d);
}
export fn compileDebug(character: u8) void {
    bindings.seL4_DebugPutChar(character);
}
