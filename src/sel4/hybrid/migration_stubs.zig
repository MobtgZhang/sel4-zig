//! 纯 Zig 占位：迁移期 smoke 路径不链接官方 C。最终语义应对齐外置 `src/` 中对应 `.c`，由 `src/sel4/**` 逐步实现，而非复制 C 进本仓库。
pub inline fn phase3BootStub() void {}
pub inline fn phase3ThreadStub() void {}
