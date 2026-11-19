//! UART selection is owned by the architecture backend.
pub const backend = @import("../arch/mod.zig").uart;
pub const init = backend.init;
pub const serialPutChar = backend.serialPutChar;
pub const serialWriteSlice = backend.serialWriteSlice;
pub const serialReadByte = backend.serialReadByte;
