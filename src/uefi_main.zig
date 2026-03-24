//! UEFI 可执行文件根模块：入口为 `main`（由 Zig `std.start` 衔接 `EfiMain`）。
//! 阶段二 2.2：`EfiMain(image_handle, system_table)` 契约说明见 `uefi/entry.zig`。
const stage2 = @import("uefi/stage2_app.zig");

comptime {
    const bc = @import("sel4/boot_comparison.zig");
    if (bc.table.len != 4) @compileError("boot_comparison table out of sync with idea1.md");
}

pub fn main() void {
    stage2.run();
}
