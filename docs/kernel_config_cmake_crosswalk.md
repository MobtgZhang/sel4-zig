# `KernelConfig`（build.zig）与上游 CMake 对照

本仓库 [`build.zig`](../build.zig) 通过 `addOptions("kernel_build_options")` 注入 [`options_types.zig`](../src/sel4/config/options_types.zig)。与官方树 CMake 选项的对应关系如下（便于后续接 `SEL4_DIR` 生成物时校验）。

| Zig `KernelConfig` / options | 上游 CMake / 配置概念 | 说明 |
|------------------------------|------------------------|------|
| `kernel_arch` (`KernelArch`) | `KernelArch`（如 `x86_64`） | 目标 ISA |
| `kernel_platform` (`KernelPlatform`) | `KernelPlatform`（如 `pc99`） | 板级/机器 |
| `max_num_nodes` | `KernelMaxNumNodes` | SMP 节点数 |
| `num_domains` | `KernelNumDomains` | 调度域 |
| `kernel_debug_build` | `KernelDebugBuild` 等调试类开关 | 调试桩 |
| `kernel_max_num_bootinfo_untyped_caps` | bootinfo untyped 上限相关生成常量 | 与 `libsel4`/`gen_config` 联动 |

## 生成物接入（`zig build sel4-codegen`）

设置 **`SEL4_BUILD`** 为已 `cmake`/`ninja` 配置好的官方构建目录（内含 `generated/`），执行：

```bash
export SEL4_BUILD=/path/to/seL4/build-xxx
zig build sel4-codegen
```

脚本 [`tools/sel4_copy_generated.sh`](../tools/sel4_copy_generated.sh) 将头文件等复制到 **`zig-cache/sel4-gen/`**，供后续 `@cImport` 或布局测试引用。

未设置 `SEL4_BUILD` 时该 step **安全跳过**，不影响默认 `zig build` / `zig build test`。

## 多架构与生成头

官方 CMake 需按目标 **`KernelArch` / `KernelPlatform`** 各配置一次构建目录；每种配置下的 `generated/`（含 `syscall.h`、`gen_config.h` 等）仅对该组合有效。为 AArch64、RISC-V 等与 Zig 侧 `syscall_numbers.zig` 对齐时，应在对应官方 build 目录上运行 `zig build sel4-codegen`（或通过脚本将不同 `SEL4_BUILD` 的输出拷到不同子目录再供 Zig 引用）。LoongArch 无官方 seL4 树时无此生成物，需自建 ABI 常量或第三方 fork。
