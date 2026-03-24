#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# 需本机安装 qemu-system-loongarch64；LoongArch 尚无官方 seL4 上游对照。
exec qemu-system-loongarch64 \
  -machine virt \
  -m 256M \
  -nographic \
  -kernel "${ROOT}/zig-out/bin/kernel-loongarch64.elf" \
  -serial stdio
