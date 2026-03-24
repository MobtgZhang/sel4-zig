//! 阶段三 3.1：与 idea1「kernelMain 调桩」等价的 **纯 Zig** 路径（不再经过 C 头/桩文件）。
const stubs = @import("migration_stubs.zig");

/// 对应 idea 中的 `kernelMain()` 过渡形态；后续可改为直接调用本仓库 Zig 内核入口。
pub fn kernelMainViaStubs() void {
    stubs.phase3BootStub();
}

test "kernel_interop zig stubs" {
    kernelMainViaStubs();
}
