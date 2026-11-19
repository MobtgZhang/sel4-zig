//! Early console multiplexes platform UART and a native or inherited framebuffer.
//! No firmware function is invoked after the boot handoff.
const uart = @import("uart.zig");
const keyboard = @import("../arch/mod.zig").backend.keyboard;
const framebuffer = @import("../drivers/framebuffer.zig");
const handoff = @import("../boot/handoff.zig");
var display: ?framebuffer.Terminal = null;
pub const DisplayKind = enum { serial_only, inherited_framebuffer, native_vga, native_ramfb };
pub var display_kind: DisplayKind = .serial_only;
pub fn init() void {
    uart.init();
}
pub fn configure(h: *const handoff.BootHandoff) !void {
    if (h.framebuffer.address == 0) return;
    var descriptor = h.framebuffer;
    display_kind = .inherited_framebuffer;
    const driver = @import("../arch/mod.zig").backend.display;
    if (driver.configure(descriptor)) |native| {
        descriptor = native;
        display_kind = driver.display_kind;
    } else |_| {}
    descriptor.address = @import("../arch/mod.zig").backend.framebufferAddress(descriptor.address);
    display = try framebuffer.Terminal.init(descriptor);
    if (display) |*terminal| terminal.bitmap = try @import("../drivers/psf.zig").Font.parse(try @import("../fs/system.zig").font("/system/fonts/IBMPlexMono.psf"));
    if (display) |*terminal| terminal.unicode_font = try @import("../drivers/unicode_font.zig").Font.parse(try @import("../fs/system.zig").font("/system/fonts/SarasaMonoSC.zguf"));
    serialWriteSlice(switch (display_kind) {
        .native_vga => "seL4-Zig | native Bochs VGA terminal | Boot Services exited\r\n",
        .native_ramfb => "seL4-Zig | native QEMU ramfb terminal | Boot Services exited\r\n",
        else => "seL4-Zig | inherited framebuffer terminal | Boot Services exited\r\n",
    });
    if (keyboard.initialize()) {
        serialWriteSlice(keyboard.name ++ " keyboard: ready\r\n");
    } else |_| {
        serialWriteSlice(keyboard.name ++ " keyboard: unavailable; use serial input\r\n");
    }
}
pub fn serialWriteSlice(bytes: []const u8) void {
    uart.serialWriteSlice(bytes);
    if (display) |*terminal| terminal.write(bytes);
}
pub fn poll() ?u8 {
    if (keyboard.poll()) |byte| return byte;
    return uart.serialReadByte();
}
pub fn readBlocking() u8 {
    while (true) {
        if (keyboard.poll()) |byte| return byte;
        if (uart.serialReadByte()) |byte| return byte;
        @import("../arch/mod.zig").relax();
    }
}

pub fn selectFont(name: []const u8) !void {
    const std = @import("std");
    const path: []const u8 = if (std.mem.eql(u8, name, "plex")) "/system/fonts/IBMPlexMono.psf" else if (std.mem.eql(u8, name, "iosevka")) "/system/fonts/Iosevka.psf" else if (std.mem.eql(u8, name, "sarasa")) "/system/fonts/SarasaMonoSC.psf" else return error.UnknownFont;
    const bitmap = try @import("../drivers/psf.zig").Font.parse(try @import("../fs/system.zig").font(path));
    if (display) |*terminal| {
        terminal.bitmap = bitmap;
        terminal.clear();
    }
}
