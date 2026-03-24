#!/usr/bin/env bash
# 通过 GRUB multiboot2 在 QEMU 中启动 zig-out/bin/kernel.elf（QEMU -kernel 对裸 ELF 常要求 PVH note）。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL="${KERNEL_ELF:-${ROOT}/zig-out/bin/kernel.elf}"
ISO="${ROOT}/zig-out/sel4-zig-bare.iso"

if [[ ! -f "${KERNEL}" ]]; then
  echo "缺少 ${KERNEL}，请先: zig build" >&2
  exit 1
fi
if ! command -v grub-mkrescue >/dev/null 2>&1; then
  echo "需要 grub-mkrescue（Debian/Ubuntu: grub-pc-bin / grub-common）。" >&2
  exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/sel4-zig-iso.XXXXXX")"
cleanup() { rm -rf "${WORK}"; }
trap cleanup EXIT

mkdir -p "${WORK}/boot/grub"
cp "${KERNEL}" "${WORK}/boot/kernel.elf"
cat >"${WORK}/boot/grub/grub.cfg" <<'GRUB'
set timeout=0
set default=0
menuentry "seL4-Zig bare" {
  multiboot2 /boot/kernel.elf
  boot
}
GRUB

mkdir -p "$(dirname "${ISO}")"
grub-mkrescue -o "${ISO}" "${WORK}" >/dev/null

exec qemu-system-x86_64 \
  -machine q35 \
  -m 128M \
  -cdrom "${ISO}" \
  -serial stdio \
  -display none \
  -no-reboot \
  -no-shutdown
