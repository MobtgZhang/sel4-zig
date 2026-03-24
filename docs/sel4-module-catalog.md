# seL4 内核源码模块清单（阶段一 / 阶段三镜像）

本文件由 `tools/gen_vendor_manifest.py` 根据 `vendor/sel4-src` 生成。

- **本地镜像文件数**: 0（`.c` + `.S`，`vendor/sel4-src`）
- **默认**: `vendor/sel4-src` 可为空；需要镜像清单时设 `FULL_VENDOR_MIRROR=1` 运行 `scripts/sync-vendor-from-upstream.sh`。
- **官方源码**: 外置 seL4 仓库的 `src/`、`include/`、`libsel4/`（本工程不内嵌 C 树）。

## 按子目录分组

