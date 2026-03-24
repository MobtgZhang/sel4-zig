# 引导 Handoff 契约（Multiboot2 / UEFI）

两种引导路径最终进入同一初始化入口：`kmain` 收到 **物理地址** 上的 [`BootHandoff`](../src/sel4/boot/handoff.zig)（或由 Multiboot2 在栈上构造）。

## `BootHandoff` 字段（ABI v1）

| 字段 | 含义 |
|------|------|
| `magic` | `L4ZHAND1` 小端 u64 |
| `version` | 当前为 `1` |
| `flags` | bit0：曾解析 Multiboot2 mmap；bit2：UEFI handoff（跳过 #PF 探测） |
| `mb2_phys` | Multiboot2 信息指针；UEFI 路径为 `0` |
| `region_count` / `regions[]` | `start`/`end` 物理地址，半开区间 |

## 路径对照

- **Multiboot2 / PVH**：`multiboot2_longmode.S` 将 `ebx` 写入 `mb2_saved`，`kmain(0)` 内调用 `fillFromMultiboot2`；PVH 入口将 `ebx` 清零并走 synthetic RAM 区。
- **UEFI**：[`kernel_elf_load.zig`](../src/uefi/kernel_elf_load.zig) 在 **RuntimeServices** 页填充 `BootHandoff`，`ExitBootServices` 后 `kmain(@intFromPtr(handoff))`。

## 产物区分

| 文件 | 用途 |
|------|------|
| `kernel.elf` | Multiboot2 + PVH note，`zig build kernel-qemu` / `kernel-qemu-direct` |
| `kernel-uefi.elf` | PIE `ET_DYN`，由 stage2 在任意物理页加载并应用 `.rela.dyn`；复制到 ESP 根为 `KERNEL.ELF`（8.3）或 `EFI/BOOT/KERN.ELF` 等（见 `kernel_elf_load.zig`） |

详见 [phase3-4-kernel-migration.md](phase3-4-kernel-migration.md)。
