//! The only common-code selection point for CPU-specific implementations.
const builtin = @import("builtin");
pub const backend = switch (builtin.cpu.arch) {
    .x86_64 => @import("x86_64/backend.zig"),
    .aarch64 => @import("aarch64/backend.zig"),
    .riscv64 => @import("riscv64/backend.zig"),
    .loongarch64 => @import("loongarch64/backend.zig"),
    else => @compileError("Unsupported kernel architecture"),
};
pub const uart = backend.uart;
pub const halt = backend.halt;
pub const relax = backend.relax;
pub const currentHardwareId = backend.currentHardwareId;

pub const user = backend.user;
