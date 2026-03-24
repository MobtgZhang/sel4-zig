# seL4-Zig 文档

本目录存放与 **seL4 → Zig / UEFI** 迁移相关的技术笔记。

## 阅读顺序

| 文档 | 说明 |
|------|------|
| [phase3-4-kernel-migration.md](./phase3-4-kernel-migration.md) | **阶段三/四**：迁移模块、PhysRegion/能力/IDT、上游 kernel.elf |
| [sel4-existing-architecture.md](./sel4-existing-architecture.md) | **阶段一**综述与启动链；**§10** 与 `ideas/idea1.md` **六阶段**对照、`zig build verify-uefi` |
| [sel4-module-catalog.md](./sel4-module-catalog.md) | **阶段一（补全）**：`vendor/sel4-src` 中 `.c`/`.S` 清单（自动生成；对照树在外置官方 `src/`） |
| [phase1-3-complete.md](./phase1-3-complete.md) | **阶段一至三**：本仓库落地结构、命令、与 idea1 文件名对照 |
| `build.zig`、`libsel4/`、`scripts/run-qemu-uefi*.sh` | **阶段二～六**：UEFI、`KernelConfig`、`libsel4`、QEMU / `make verify-uefi` |
| [sel4-existing-architecture.md](./sel4-existing-architecture.md) **§11** | 多架构裸 ELF：`kernel-aarch64.elf` / `kernel-riscv64.elf` / `kernel-loongarch64.elf` 与 `zig build kernel-qemu-*` |

上游官方手册与白皮书见：[docs.sel4.systems](https://docs.sel4.systems)。
