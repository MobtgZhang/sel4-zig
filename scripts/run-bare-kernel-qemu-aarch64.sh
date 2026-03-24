#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec qemu-system-aarch64 \
  -machine virt \
  -cpu cortex-a57 \
  -m 256M \
  -nographic \
  -kernel "${ROOT}/zig-out/bin/kernel-aarch64.elf" \
  -serial stdio
