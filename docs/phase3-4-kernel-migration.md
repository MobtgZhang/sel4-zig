# 阶段三 / 四：内核迁移与 Zig 核心模型

对应 [ideas/idea1.md](../ideas/idea1.md) **阶段三**（渐进 C→Zig）与 **阶段四**（能力、内存、IDT 等 Zig 化骨架）。

## 已落地内容

### 迁移计划阶段 1～2（裸机 Zig 内核骨架）

- **产物**：`zig build` 安装 **`zig-out/bin/kernel.elf`**（Multiboot2 + Xen PVH `.note.Xen`）与 **`zig-out/bin/kernel-uefi.elf`**（`ET_DYN` + PIE，UEFI 在任意空闲页加载并处理 `.rela.dyn`）。Zig 根文件为 [`src/sel4/kmain.zig`](../src/sel4/kmain.zig)。
- **链接**：[`linker/kernel_x86_64.ld`](../linker/kernel_x86_64.ld) / [`linker/kernel_uefi_x86_64.ld`](../linker/kernel_uefi_x86_64.ld)，`image_base = 0x100000`；内核模块 **`ReleaseSmall` + strip + `-fno-unwind-tables`**。
- **IDT**：[`idt_lite.zig`](../src/sel4/baremetal/idt_lite.zig) re-export [`arch/x86_64/idt.zig`](../src/sel4/arch/x86_64/idt.zig)；[`isr_de.S`](../src/sel4/baremetal/isr_de.S)、[`isr_pf.S`](../src/sel4/baremetal/isr_pf.S) 与 [`api/faults.zig`](../src/sel4/api/faults.zig) 提供 `#DE` / `#PF` 桩。
- **QEMU 双轨**：**`zig build kernel-qemu-direct`** 使用 `qemu -kernel kernel.elf`（依赖 PVH note）；**`zig build kernel-qemu`** 仍可用 GRUB ISO（[`scripts/run-bare-kernel-qemu.sh`](../scripts/run-bare-kernel-qemu.sh)）。依赖：`grub-pc-bin` / `xorriso` 等。
- **Handoff**：Multiboot2 与 UEFI 共用 [`BootHandoff`](../src/sel4/boot/handoff.zig)，说明见 [boot-handoff.md](boot-handoff.md)。

### 阶段三

- **对照索引**：官方 `.c`/`.S` 在 **仓库外** 的 seL4 树（默认并列 **`../seL4/src`**）。本仓库 Zig 用 `upstream_rel` 记录相对该 `src/` 的路径，便于逐文件迁移。可选：`FULL_VENDOR_MIRROR=1` + `scripts/sync-vendor-from-upstream.sh` 复制到 `vendor/` 并刷新清单。
- **迁移桩（纯 Zig）**：`src/sel4/hybrid/migration_stubs.zig`、`boot_bridge.zig`（无 `@cImport`/无 libc）。
- **x86_64 原语**：`src/sel4/arch/x86_64/machine.zig`、`tlb.zig`、`mmu.zig`（复杂页表仍在上游 `vspace.c`）。
- **IPC 路径占位**：`src/sel4/kernel/ipc_dispatch.zig`，与 `api/syscall.zig` / `api/ipc.zig` 相连。上游无 `kernel/ipc.c`，入口为 `api/syscall.c`。

### 阶段四（骨架）

| 文件 | idea1 小节 | 说明 |
|------|------------|------|
| `src/sel4/model/capability.zig` | 4.1 | `CapRaw` 对齐 `cap_t`（`words[2]` + 类型位域）；高层 `union(enum)` 仍保留 |
| `src/sel4/mm/phys_region.zig` | 4.2 | `PhysRegion` + `fromUefiMemoryMapSlice` |
| `src/sel4/arch/x86_64/idt.zig` | 4.3 | `IdtEntry` `packed struct`（16 字节） |
| `src/uefi/stage2_app.zig` | — | 打印配置与 `PhysRegion`；若存在 `kernel-uefi.elf` 则 `ExitBootServices` 并跳入 `kmain` |

## 上游 seL4 内核（本仓库不提供 CMake 预设）

官方 **C 内核**仍在 **外置** seL4 仓库内用 **CMake** 构建（见 [Getting started](https://docs.sel4.systems/GettingStarted.html) 与其根目录 `CMakeLists.txt`）。本 Zig 仓 **不包含** 该树；典型依赖包括 `cmake`、`ninja`、`gcc`、`python3-yaml` 等。

自行选择构建目录与初始缓存，例如 pc99 + x86_64 需在 `cmake` 时指定 `KernelPlatform` / `KernelArch` 等（与上游文档一致）。产物常见为 **`kernel.elf`**（**官方 C 内核**）；`make run` 默认从 `$(SEL4_DIR)/build-sel4-zig/kernel.elf` 复制到 ESP（可通过 `SEL4_BUILD` / `KERNEL_ELF` 覆盖）。勿与本仓库 **Zig 裸机** `zig-out/bin/kernel.elf` / `kernel-uefi.elf` 混淆（见根目录 [README](../README.md)）。

## 测试

```bash
make test
# 或 zig build test
```

涵盖：`mirror_manifest`、`registry`、x86 `cpuid`、迁移桩、阶段四 `capability` / `idt` 等。
