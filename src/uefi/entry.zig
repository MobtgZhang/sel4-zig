//! 阶段二 2.2：UEFI 入口说明（对照 ideas/idea1.md `efiMain`）。
//!
//! idea1 草图：
//! ```zig
//! pub fn efiMain(image_handle: Handle, system_table: *SystemTable) callconv(.c) Status
//! ```
//! 本工程由 `lib/std/start.zig` 提供等价衔接：`EfiMain` → `root.main()`，并预先设置
//! `std.os.uefi.handle` 与 `std.os.uefi.system_table`（见 `std.start` 的 `uefi` 分支）。
//!
//! 后续步骤（内存映射、GOP、`ExitBootServices`、跳内核）在 `uefi/stage2_app.zig` 等处演进。
//! Multiboot 与 UEFI 差异表见 `sel4/boot_comparison.zig`。

pub const std_start_handles_entry = true;
