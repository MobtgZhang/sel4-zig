# 阶段一：seL4 现有内核架构（源码级）

本文描述 **官方 seL4 内核（C）** 的架构，供 **对照阅读**；请在 **仓库外** 打开你 clone 的 seL4 树（默认与 `seL4-Zig` 并列的 **`../seL4`**）。`seL4-Zig` **不** 内嵌该 C 树，目标是 **`src/sel4/**/*.zig`** 逐步替代其中逻辑。

**阶段三补充**：各 Zig 模块以 `upstream_rel` / `upstream_tree` 标注对应官方 `src/` 路径。需要本地 C 镜像与清单时：`FULL_VENDOR_MIRROR=1 bash scripts/sync-vendor-from-upstream.sh`，再 `python3 tools/gen_vendor_manifest.py` 生成 [sel4-module-catalog.md](./sel4-module-catalog.md) 与 `mirror_manifest.zig`。

---

## 1. 技术栈与仓库角色

| 层次 | 现状 |
|------|------|
| 实现语言 | C + 汇编（`.S`） |
| 构建 | CMake（`CMakeLists.txt`、`config.cmake`、`configs/seL4Config.cmake` 等） |
| 配置与代码生成 | Python（`tools/`：`config_gen.py`、`bitfield_gen.py`、`hardware_gen.py`、`syscall_header_gen.py` 等） |
| 典型引导（x86 pc99） | Multiboot / Multiboot2（GRUB 等）；ARM/RISC-V 则由各平台 `head.S` + Bootloader/FDT 约定 |

内核仓库 **不包含** 完整用户态系统；初始用户映像通常以 **Multiboot 模块**等形式由引导加载器交给内核（x86 上 `boot_sys.c` 会检查至少一个 boot module）。

---

## 2. 顶层目录结构（内核仓库内）

```
seL4/
├── CMakeLists.txt      # 主构建入口
├── config.cmake        # 内核特性、与验证相关的配置选项
├── configs/            # seL4Config.cmake 等架构/平台选择
├── include/            # 对内可见的 C 头文件（kernel、object、arch、plat…）
├── libsel4/            # 用户态可见的 API 头文件与桩代码生成工具（syscall 等）
├── src/                # 内核实现主体
├── tools/              # CMake 引用的脚本与生成器
└── gdb/                # 调试相关（按需）
```

**`include/` 与 `src/` 的分工**：类型、对象布局、内联与宏多在 `include/`；具体算法与状态机在 `src/`。架构相关头文件在 `include/arch/<arch>/…`，与 `src/arch/<arch>/…` 成对出现。

---

## 3. `src/` 子系统划分

### 3.1 与架构无关（或弱相关）的核心代码

| 路径 | 职责 |
|------|------|
| `src/kernel/` | 引导后期与抽象模型贴近的逻辑：**`boot.c`**（空闲内存、`rootserver` 对象、初始线程与 BootInfo 等）、**`thread.c`**（调度与线程状态）、**`cspace.c`**、**`faulthandler.c`**、**`stack.c`**、**`sporadic.c`**（Sporadic 服务器相关） |
| `src/object/` | 内核对象：**`cnode`/`tcb`/`endpoint`/`notification`/`reply`/`untyped`/`interrupt`/`schedcontext`/`schedcontrol`/`objecttype`** |
| `src/api/` | 系统调用分发与故障：**`syscall.c`**（`handleSyscall`）、**`faults.c`** |
| `src/fastpath/` | IPC 等 **快路径** 的 C 逻辑入口（常与 arch 下汇编配合） |
| `src/model/` | 抽象状态与 SMP 等：**`statedata.c`**、**`smp.c`**、**`preemption.c`** |
| `src/machine/` | 跨平台机器层共性（如 **`capdl.c`**、**`registerset.c`**、**`fpu.c`** 等，具体因配置而异） |
| `src/smp/` | 锁、IPI 等 |
| `src/drivers/` | 定时器、串口、SMMU 等 **驱动片段**（由 CMake 按平台勾选） |
| `src/util.c`、`src/string.c`、`src/inlines.c` | 通用工具与内联聚合 |

### 3.2 架构层 `src/arch/<arch>/`

每种架构下有 **machine**（硬件原语）、**kernel**（引导、地址空间、陷阱）、**object**（架构相关对象与 cap）、**api**、**model** 等子目录。

**x86 示例（与本仓库一致）：**

- `src/arch/x86/64/head.S`：**Multiboot 入口**；在保护模式下准备页表、开启长模式，再进入 64 位入口；与 **`boot_sys`** 衔接。
- `src/arch/x86/kernel/boot_sys.c`：解析 Multiboot(2) 信息、加载 **initial userland ELF**、映射内核窗口、调用架构无关引导链。
- `src/arch/x86/kernel/boot.c`：**`init_sys_state`** — 在 CPU 已就绪的前提下初始化 **本节点** 内核状态（与抽象规范中的引导阶段对应）；含 **`arch_init_freemem`**，最终调用通用 **`init_freemem`**（定义在 `src/kernel/boot.c`）。
- `src/arch/x86/c_traps.c`：异常/系统调用入口的 C 侧，调用 **`handleSyscall`**（`src/api/syscall.c`）。
- `src/arch/x86/kernel/vspace.c`、`thread.c`、`traps.S`、`multiboot.S` 等：分页、APIC、陷阱、Multiboot 头。

**AArch64 / RISC-V**：ARM 系 64 位入口在 **`arch/arm/64/head.S`** 等；同样有 `kernel/boot.c`、`c_traps.c` 等，但 **固件/设备树/入口约定** 与 x86 Multiboot 不同；通用 **`src/kernel/boot.c`** 仍承担大量「创建根任务、Untyped、BootInfo」等逻辑。

> **勘误说明**：规划草案中曾写 `src/arch/x86/init.c`。在当前 seL4 树中 **不存在该文件**；x86 上「物理内存与引导信息」相关逻辑主要分布在 **`arch/x86/kernel/boot_sys.c`** 与 **`arch/x86/kernel/boot.c`**，与通用 **`src/kernel/boot.c`** 协同。

### 3.3 平台层 `src/plat/<platform>/`

描述 **具体板卡/QEMU 机器**：`config.cmake`、设备树 overlay（`.dts`）、以及 `machine/` 下的 **`hardware.c`**、**`acpi.c`**（pc99）等。平台选择与内存布局通过 CMake + `hardware_gen` 等与 **`include/plat/...`** 头文件关联。

---

## 4. 启动路径（以 x86_64 + Multiboot 为主）

下列顺序便于阅读源码时「从入口跟到第一个用户线程」：

1. **`src/arch/x86/64/head.S`**  
   Multiboot 进入 → 建立 64 位分页与长模式 → 调用 **`common_init`** 等 → 最终跳到 **`boot_sys`**（见该文件中 `jmp boot_sys` 一类目标）。

2. **`src/arch/x86/kernel/boot_sys.c` — `boot_sys(multiboot_magic, mbi)`**  
   - 识别 Multiboot 1 / 2；  
   - **`try_boot_sys_mbi1` / `try_boot_sys_mbi2`** 填充 **`boot_state`**（内存区、模块、ACPI、mmap 等）；  
   - **`try_boot_sys()`**：映射内核窗口、加载用户 ELF、调用 **`init_sys_state`**；  
   - 成功后 **`schedule()`**、**`activateThread()`** 进入正常运行。

3. **`src/arch/x86/kernel/boot.c` — `init_sys_state(...)`**  
   架构相关的 IRQ 初始化、**`arch_init_freemem`**（把内核映像等纳入保留区后调用通用 **`init_freemem`**）、创建根能力空间、初始线程等。

4. **`src/kernel/boot.c`**  
   **`init_freemem`**、**`create_rootserver_objects`**、**`create_initial_thread`**、**`create_untypeds`**、**`bi_finalise`** 等与 **规范中的引导阶段** 直接对应的大量函数。

5. **`src/kernel/thread.c` + `src/api/syscall.c`**  
   调度与系统调用路径在运行期由此展开。

**AArch64 / RISC-V**：入口在各自 **`src/arch/<arch>/head.S`**（ARM 系 AArch64 代码在 **`arch/arm/64/`**），C 侧常见模式为 **`try_init_kernel`**（在 `arch/arm/kernel/boot.c`、`arch/riscv/kernel/boot.c`），再与通用 **`src/kernel/boot.c`** 汇合。细节依赖平台 CMake 与设备树。

---

## 5. 能力、对象与系统调用（概念与代码落点）

- **能力（cap）与 CNode**：`include/object/cap.h`、`src/object/cnode.c`；槽位与类型由 **bitfield 生成**（`structures*.bf` + `bitfield_gen.py`）。
- **TCB / 调度**：`src/object/tcb.c`、`src/kernel/thread.c`；MCS 相关另有 **`schedcontext.c`**、**`schedcontrol.c`**。
- **IPC**：端点 **`src/object/endpoint.c`**、通知 **`notification.c`**、应答 **`reply.c`**；快路径 **`src/fastpath/fastpath.c`** + 各 arch 的 **`arch/.../fastpath/`**（含汇编）。
- **系统调用**：**`src/api/syscall.c`** 中 **`handleSyscall`**；入口在 **`src/arch/*/c_traps.c`**。
- **故障与异常**：**`src/api/faults.c`**、`src/kernel/faulthandler.c`**，与 arch 陷阱处理衔接。

---

## 6. `libsel4/`（用户态接口）

内核侧实现与 **用户态 stub** 的接口定义、常量、类型在 **`libsel4/`** 中按 **arch / platform** 组织，例如：

- `sel4_arch_include/`、`sel4_plat_include/`：各架构与平台的 **`constants.h`**、**`types.h`**、**`syscalls.h`** 等；
- `tools/syscall_stub_gen.py`：与内核 syscall 编号生成配套。

迁移到 Zig 时，若需保持用户程序兼容，需对照这些头文件与调用约定（寄存器/系统调用指令因架构而异）。

---

## 7. 构建与配置要点（阅读 CMake 时）

- **`KernelArch` / `KernelPlatform`**：决定纳入哪些 `src/arch`、`src/plat` 源文件与 `include` 路径。
- **`config_gen.py` / `bitfield_gen.py`**：生成 **`gen_config.h`**、位域结构体等，**无生成步骤则无法编译**。
- **链接脚本**：如 pc99 的 **`src/plat/pc99/linker.lds`**，定义 **`KERNEL_ELF_*`**、boot stack 等符号，与 **`boot_sys.c`**、`head.S` 中的 `extern` 符号一致。

---

## 8. 阶段一推荐阅读清单（面向后续 Zig + UEFI）

| 优先级 | 路径 | 目的 |
|--------|------|------|
| 高 | `src/arch/x86/64/head.S` | 当前引导入口与模式切换 |
| 高 | `src/arch/x86/kernel/boot_sys.c` | Multiboot 信息 → 内存与用户映像 |
| 高 | `src/kernel/boot.c` | 通用引导：空闲内存、根对象、初始线程 |
| 高 | `src/arch/x86/kernel/boot.c` | x86 特有引导与 `init_sys_state` |
| 中 | `src/api/syscall.c`、`src/arch/x86/c_traps.c` | 系统调用与陷阱边界 |
| 中 | `src/kernel/thread.c`、`src/object/tcb.c` | 调度与线程 |
| 中 | `src/fastpath/fastpath.c` + arch fastpath | 性能敏感 IPC 路径 |
| 中 | `CMakeLists.txt`、`config.cmake`、`tools/*.py` | 构建与生成依赖 |
| 低 | 目标平台的 `src/plat/<plat>/` | 设备与链接布局 |

若目标改为 **UEFI**：需重点对比「**Multiboot 信息结构**」与「**UEFI Memory Map + ExitBootServices**」的差异，并识别 **`boot_sys.c` / `head.S`** 中哪些步骤可被固件替代、哪些仍须在内核最早阶段完成（页表、高半核映射等）。官方手册中的 *Boot*、*Memory*、*IPC* 章节可与上述文件对照阅读。

---

## 9. 形式化验证说明（与迁移相关）

当前 **L4.verified** 证明针对 **既有 C 实现与配置**。任何大规模语言替换（如 Zig）都会 **使现有证明不再直接适用**；若需高保障认证，需单独规划验证或新证明工程。此点不影响阶段一对 **架构与数据流** 的理解，但是 **项目决策层面的硬约束**。

---

## 10. 与 `ideas/idea1.md` 六阶段对照（本仓库落地）

| 阶段 | idea1.md 要点 | seL4-Zig 落点 |
|------|----------------|----------------|
| 一 | 目录结构、`head.S` / `boot_sys` / `boot.c` 通读 | 本文 §2–§5；`src/sel4/idea1_phases.zig`（路径索引） |
| 二 | Zig UEFI 目标、`efiMain`、Multiboot↔UEFI 差异 | `build.zig`（UEFI triple）、`uefi/entry.zig`、`sel4/boot_comparison.zig`、`src/uefi_main.zig` |
| 三 | Zig 调 C、`invlpg`、`addAssemblyFile`、迁移顺序 | `hybrid/c_kernel_interop.zig`、`arch/x86_64/tlb.zig`、`arch/aarch64_bundle.zig`、`migration_priority.zig`、`fastpath/placeholder_x86_64.s` + `build.zig`（x86_64 主机） |
| 四 | Capability、`PhysRegion`、`IdtEntry` | `model/capability.zig`、`mm/phys_region.zig`、`arch/x86_64/idt.zig` |
| 五 | `KernelConfig`、`addOptions`、`libsel4` syscall | `build.zig` 中 `KernelConfig`、`kernel_build_options`、`libsel4/src/*.zig` |
| 六 | QEMU+OVMF、测试层级、形式化验证代价 | `scripts/run-qemu-uefi*.sh`、`zig build verify-uefi`、`zig build test`；验证证明见 §9 |

### 6.2 测试策略（idea1 表格）

| 层级 | 工具 | 本仓库 |
|------|------|--------|
| 单元测试 | `zig test` | `zig build test`（`src/sel4/migration_tests.zig`） |
| 集成测试 | QEMU + 串口 | `zig build qemu` / `zig build verify-uefi` / `make run` |
| 形式化验证 | 暂不可用 | 同 §9：Zig 重写不继承 L4.verified |

---

## 11. seL4-Zig 多架构落地状态（摘要）

| ISA | 裸 ELF 产物 | 引导 / 串口 | 上游 C 对照 |
|-----|-------------|-------------|-------------|
| x86_64 | `kernel.elf`（Multiboot2 / PVH） | COM1 | `arch/x86/64` |
| aarch64 | `kernel-aarch64.elf` | PL011（`plat/qemu_aarch64_virt.zig`） | `arch/arm/64` + FDT（`boot/fdt.zig`） |
| riscv64 | `kernel-riscv64.elf` | NS16550 @ `0x10000000` | `arch/riscv` + FDT |
| loongarch64 | `kernel-loongarch64.elf` | 桩（无官方 seL4） | 无；见 `arch/loongarch64_bundle.zig` |

QEMU：`zig build kernel-qemu-aarch64` / `kernel-qemu-riscv64` / `kernel-qemu-loongarch64`（脚本在 `scripts/run-bare-kernel-qemu-*.sh`）。UEFI stage2 仍为 x86_64（`BOOTX64`）。

---

*文档版本：对照本仓库 `seL4` 内核源码树整理；若上游 seL4 更新，请以实际路径为准。*
