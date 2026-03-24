//! 历史占位：真实 UEFI 路径见 `uefi/kernel_elf_load.zig` → `kmain(handoff_phys)`。
const boot_bridge = @import("boot_bridge.zig");

/// 与 idea1 示例中的 `kernelMain` 命名一致；仍用于 C 对照/桩链，**非**当前 UEFI 主入口。
export fn kernelMain() callconv(.c) void {
    boot_bridge.callBootStub();
}
