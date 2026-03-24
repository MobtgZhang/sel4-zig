# 链接脚本说明

- **UEFI (`BOOTX64.efi`)**：目标为 PE/COFF，由 Zig/LLD 生成，**不使用** ELF 的 `.ld` 脚本。
- **后续 seL4 内核 ELF**（Multiboot 或自定义加载）：可参考上游 `seL4/src/plat/pc99/linker.lds`，在本仓库增加 `linker/kernel_x86_64.ld` 并在 `build.zig` 中通过 `exe.setLinkerScript()` 指定。
