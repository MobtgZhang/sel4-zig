#!/usr/bin/env bash
# 阶段 C：将官方 seL4 CMake 构建目录中的 generated/ 复制到本仓库 zig-cache/sel4-gen。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -z "${SEL4_BUILD:-}" ]]; then
  echo "sel4-codegen: 跳过（未设置 SEL4_BUILD 指向已配置的 seL4 构建目录）"
  exit 0
fi
if [[ ! -d "${SEL4_BUILD}/generated" ]]; then
  echo "sel4-codegen: 未找到 ${SEL4_BUILD}/generated，跳过" >&2
  exit 0
fi
DEST="${ROOT}/zig-cache/sel4-gen"
mkdir -p "${DEST}"
cp -a "${SEL4_BUILD}/generated/." "${DEST}/"
echo "sel4-codegen: 已复制到 ${DEST}"
