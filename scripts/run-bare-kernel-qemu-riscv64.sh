#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec qemu-system-riscv64 \
  -machine virt \
  -m 256M \
  -bios none \
  -nographic \
  -kernel "${ROOT}/zig-out/bin/kernel-riscv64.elf" \
  -serial stdio
