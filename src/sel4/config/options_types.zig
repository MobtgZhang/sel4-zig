//! 阶段五：与 CMake `KernelArch` / `KernelPlatform` 等对应的编译期枚举（供 `build.zig` + `addOptions` 使用）。
pub const KernelArch = enum {
    x86_64,
    aarch64,
    riscv64,
    loongarch64,
};

pub const KernelPlatform = enum {
    pc99,
    /// QEMU virt 机器上的 AArch64（与上游 `qemu-arm-virt` 平台对应）。
    qemu_aarch64_virt,
    /// QEMU `virt` 板上的 RISC-V 64（与上游 RISC-V QEMU 平台对应）。
    qemu_riscv64_virt,
    /// QEMU LoongArch `virt`（无官方 seL4 上游树；占位供实验构建）。
    qemu_loongarch64_virt,
};
