# seL4-Zig

把 **seL4 内核从 C/汇编逐步迁到 Zig** 的实验工程：本仓库里的 **`src/sel4/**/*.zig`** 才是目标实现与迁移骨架；**不** 在仓内存放官方整棵 C 内核树（那不是「移植」，只是拷贝）。

**官方 C 对照与 CMake 构建**：请单独 clone [seL4](https://github.com/seL4/seL4)（或与 `seL4-Zig` **并列**的 `../seL4`），或通过环境变量 **`SEL4_DIR`** 指向该根目录。各 Zig 文件里的 `upstream_rel` / `upstream_tree` 仅标注「对应官方 `src/` 下哪份 `.c`/子树」，便于逐模块对照重写。

可选：设 **`FULL_VENDOR_MIRROR=1`** 运行 `scripts/sync-vendor-from-upstream.sh`，把 `.c`/`.S` 复制到 `vendor/` 仅用于离线浏览或生成 `mirror_manifest`；**不** 改变「实现语言应为 Zig」的目标。

## 构建（Makefile 或 Zig）

```bash
make                 # zig build → zig-out/bin/BOOTX64.efi（x86_64 UEFI）
make test            # Zig 迁移模块单元测试
make qemu            # QEMU + OVMF，仅 UEFI
zig build kernel-qemu        # 裸机 Zig kernel.elf（GRUB ISO + 串口）
zig build kernel-qemu-direct # qemu -kernel kernel.elf（PVH note，无 ISO）
zig build verify-kernel-handoff # OVMF + ESP 上 kernel-uefi.elf，串口断言 kernelInit
make run             # 官方 **C** kernel.elf 放到 ESP（见下）
```

### 两枚 `kernel.elf`（勿混淆）

| 产物 | 来源 | 用途 |
|------|------|------|
| **`zig-out/bin/kernel.elf`** | 本仓库 Zig（Multiboot2 + PVH） | `kernel-qemu` / `kernel-qemu-direct` |
| **`zig-out/bin/kernel-uefi.elf`** | 本仓库 Zig（UEFI 专用链接脚本） | 复制到 FAT ESP 根或 `EFI/BOOT/`，由 stage2 加载 |
| **官方树里的 `kernel.elf`** | 外置 seL4 CMake | `make run` 对照用 C 内核 |

`make run` 默认在 **`${SEL4_DIR}/build-sel4-zig/kernel.elf`**（`SEL4_DIR` 默认为 `../seL4`）查找 **官方 C** 镜像；可用 **`KERNEL_ELF`** / **`SEL4_BUILD`** 覆盖。

可选：`export SEL4_BUILD=... && zig build sel4-codegen` 将官方 `generated/` 复制到 `zig-cache/sel4-gen/`（见 [docs/kernel_config_cmake_crosswalk.md](docs/kernel_config_cmake_crosswalk.md)）。

```bash
zig build
zig build test
zig build qemu
```

## 阶段三 / 四（相对 [ideas/idea1.md](ideas/idea1.md)）

- **阶段三**：在 `src/sel4/**` 用 Zig 表达内核子系统骨架与桩；与官方 `syscall.c`、`boot.c` 等 **一一对照**，由 `upstream_*` 标路径。
- **阶段四**：`model/capability.zig`、`mm/phys_region.zig`、`arch/x86_64/idt.zig` 等。

详见 [docs/phase3-4-kernel-migration.md](docs/phase3-4-kernel-migration.md)。

## 文档

| 文档 | 内容 |
|------|------|
| [docs/phase3-4-kernel-migration.md](docs/phase3-4-kernel-migration.md) | 迁移策略、外置内核构建、`make run` |
| [docs/boot-handoff.md](docs/boot-handoff.md) | Multiboot2 / UEFI 共用 `BootHandoff` |
| [docs/kernel_config_cmake_crosswalk.md](docs/kernel_config_cmake_crosswalk.md) | `KernelConfig` 与 CMake 对照、`sel4-codegen` |
| [docs/phase1-3-complete.md](docs/phase1-3-complete.md) | 阶段一至三总览 |
| [docs/sel4-existing-architecture.md](docs/sel4-existing-architecture.md) | 官方架构导读（对照外置树阅读） |
| [ideas/idea1.md](ideas/idea1.md) | 路线图 |

UEFI 输出参考 [ZirconOS](https://github.com/MobtgZhang/ZirconOS/tree/main/boot/zbm/uefi)。
