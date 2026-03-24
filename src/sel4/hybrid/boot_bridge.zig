//! 阶段三：Zig 侧调用迁移桩（纯 Zig，无 `@cImport`）。
const stubs = @import("migration_stubs.zig");

pub fn callBootStub() void {
    stubs.phase3BootStub();
}

pub fn callThreadStub() void {
    stubs.phase3ThreadStub();
}
