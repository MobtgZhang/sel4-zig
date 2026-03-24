#!/usr/bin/env bash
# 可选：从 **仓库外** 官方 seL4 树复制 .c/.S、include、libsel4 到 vendor/ 并生成 mirror_manifest。
# 默认不 rsync（本仓库以 Zig 迁移为主，不内嵌 C 内核树）。
set -euo pipefail
ZIG_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -n "${SEL4_DIR:-}" ]]; then
  SEL4_ROOT="${SEL4_DIR}"
else
  SEL4_ROOT="$(cd "${ZIG_ROOT}/.." && pwd)/seL4"
fi

if [[ "${FULL_VENDOR_MIRROR:-}" != "1" ]]; then
  echo "未设置 FULL_VENDOR_MIRROR=1，跳过 rsync（对照用官方树默认路径: ${SEL4_ROOT}）。"
  mkdir -p "${ZIG_ROOT}/vendor/sel4-src"
  exec python3 "${ZIG_ROOT}/tools/gen_vendor_manifest.py"
fi

if [[ ! -d "${SEL4_ROOT}/src" ]]; then
  echo "未找到 ${SEL4_ROOT}。请 clone 官方 seL4 到并列目录，或 export SEL4_DIR=... 指向其根目录。" >&2
  exit 1
fi
mkdir -p "${ZIG_ROOT}/vendor"
rsync -a --delete --prune-empty-dirs --include='*/' --include='*.c' --include='*.S' --exclude='*' \
  "${SEL4_ROOT}/src/" "${ZIG_ROOT}/vendor/sel4-src/"
rsync -a --delete "${SEL4_ROOT}/include/" "${ZIG_ROOT}/vendor/sel4-include/"
rsync -a --delete "${SEL4_ROOT}/libsel4/" "${ZIG_ROOT}/vendor/libsel4/"

rm -rf "${ZIG_ROOT}/vendor/sel4-src/arch/arm/32"
rm -rf "${ZIG_ROOT}/vendor/sel4-src/arch/arm/armv/armv7-a"
rm -rf "${ZIG_ROOT}/vendor/sel4-src/arch/arm/armv/armv8-a/32"

echo "已完整镜像（AArch64 导向剔除 AArch32）。生成清单…"
exec python3 "${ZIG_ROOT}/tools/gen_vendor_manifest.py"
