# 阶段一至三：本仓库落地说明

**阶段四～六**（能力/PhysRegion/IDT、`KernelConfig`、libsel4、QEMU 验证）见 [sel4-existing-architecture.md §10](./sel4-existing-architecture.md) 与 `ideas/idea1.md`。

## 阶段一（架构理解）

| 产物 | 路径 |
|------|------|
| 架构综述 | [sel4-existing-architecture.md](./sel4-existing-architecture.md) |
| **全量** `.c`/`.S` 文件级清单（自动生成） | [sel4-module-catalog.md](./sel4-module-catalog.md) |

从 **外置** 官方 seL4（默认并列 **`../seL4`**，或设置 **`SEL4_DIR`**）**镜像到 vendor/** 并刷新清单：

```bash
./scripts/sync-vendor-from-upstream.sh
```

若已手动更新 `vendor/sel4-src`，仅刷新清单：

```bash
python3 tools/gen_vendor_manifest.py
```

## 阶段二（x86_64 UEFI）

| 产物 | 说明 |
|------|------|
| `src/uefi_main.zig` | UEFI 可执行文件根模块（`main`） |
| `src/uefi/stage2_app.zig` | 阶段二逻辑：内存映射、GOP、串口输出 |
| `src/uefi/console.zig` | 文本输出（ZirconOS 风格小栈策略） |
| `src/uefi/entry.zig` | 入口语义说明（`EfiMain` 由 `std.start` 提供） |
| `linker/README.md` | 说明 UEFI 使用 PE/COFF，无需 ELF `.ld` |
| `scripts/run-qemu-uefi.sh` | QEMU + OVMF 运行 |

构建与运行：

```bash
zig build
zig build qemu
```

## 阶段三（渐进 C ↔ Zig）

### 对照用官方 C 树（不在本仓库）

完整 seL4 **C** 工程请单独 clone，与 `seL4-Zig` 并列（**`../seL4`**）或 **`export SEL4_DIR=...`**。Zig 模块用 **`upstream_rel` / `upstream_tree`** 记录相对官方 **`src/`** 的路径。若需要 `vendor/sel4-src` 副本与清单：`FULL_VENDOR_MIRROR=1 bash scripts/sync-vendor-from-upstream.sh`，再 `python3 tools/gen_vendor_manifest.py`。

### Zig 侧模块（外围/原语）

| 类型 | 路径 |
|------|------|
| x86_64 寄存器/CPUID/CR | `src/sel4/arch/x86_64/machine.zig` |
| TLB `invlpg` | `src/sel4/arch/x86_64/tlb.zig` |
| MMU 说明 + 指向上游 `vspace.c` | `src/sel4/arch/x86_64/mmu.zig` |
| 架构树索引 | `src/sel4/arch/x86_bundle.zig`、`aarch64_bundle.zig`、`riscv_bundle.zig` |
| 与 idea1 优先级对应的 `kernel`/`object`/`api`/… | `src/sel4/<子系统>/*.zig`（`upstream_rel` 相对外置官方 `src/`） |
| 全模块注册 | `src/sel4/registry.zig` |
| 可选镜像清单 | `src/sel4/mirror_manifest.zig`（默认可为 0 条） |

### 迁移桩（纯 Zig，无 C/libc）

- `src/sel4/hybrid/migration_stubs.zig`、`boot_bridge.zig`、`c_kernel_interop.zig`
- 示例：`kernel/boot.zig` 的 `zigSmokeBootStub()`、`kernel/thread.zig` 的 `zigSmokeThreadStub()`
- 预留导出：`src/sel4/hybrid/kernel_export.zig` 中的 `kernelMain`（供后续 UEFI handoff 链接）

> **说明**：真实 `init_kernel` / 完整 **C** 内核链接仍在外置 seL4 树内用 **CMake**；本仓库 `zig build test` 只测 Zig 迁移模块，不链接官方内核。

### 测试

```bash
zig build test
```

覆盖：`mirror_manifest`（默认可为 0）、`registry` 全量引用、`cpuid`、迁移桩。

## 与 idea1 文件名的映射

| idea1（旧名） | 现网 seL4 / 本仓库 |
|----------------|-------------------|
| `arch/x86/64/machine.c` | `arch/x86/machine/*.c` + `64/machine/*.c`；Zig 原语在 `machine.zig` |
| `arch/x86/64/tlb.c` | 合入 `vspace.c` 等；Zig `tlb.zig` |
| `arch/x86/64/mmu.c` | `arch/x86/kernel/vspace.c`、`arch/x86/64/kernel/vspace.c` |
| `kernel/ipc.c` | `api/syscall.c` + 各 `object/*.c`；`api/ipc.zig` 说明 |

## 阶段三 / 四（续）

见 **[phase3-4-kernel-migration.md](./phase3-4-kernel-migration.md)**（含上游内核构建说明与 Zig 核心模型）。
