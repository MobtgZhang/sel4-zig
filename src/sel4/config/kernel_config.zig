//! 阶段五 5.1：`KernelConfig` 的 Zig 侧视图；具体数值由 `build.zig` 经 `addOptions` 注入 `kernel_build_options`。
//! 枚举定义与 `options_types.zig` 保持一致并由 `build.zig` 传入 `addOptions`。
const kb = @import("kernel_build_options");

pub const KernelArch = @TypeOf(kb.kernel_arch);
pub const KernelPlatform = @TypeOf(kb.kernel_platform);

pub const arch: KernelArch = kb.kernel_arch;
pub const platform: KernelPlatform = kb.kernel_platform;
pub const max_num_nodes: u32 = kb.max_num_nodes;
pub const num_domains: u32 = kb.num_domains;

pub const kernel_debug_build: bool = kb.kernel_debug_build;
pub const kernel_max_num_bootinfo_untyped_caps: u32 = kb.kernel_max_num_bootinfo_untyped_caps;

test "kernel build options visible" {
    const std = @import("std");
    try std.testing.expect(max_num_nodes >= 1);
    try std.testing.expect(num_domains >= 1);
    _ = @intFromEnum(arch);
    _ = @intFromEnum(platform);
}
