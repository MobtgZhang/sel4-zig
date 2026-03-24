#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EFI_SRC="${ROOT}/zig-out/bin/BOOTX64.efi"

if [[ ! -f "${EFI_SRC}" ]]; then
  echo "找不到 ${EFI_SRC}，请先在 ${ROOT} 下执行: zig build" >&2
  exit 1
fi

ESP="$(mktemp -d "${TMPDIR:-/tmp}/sel4-zig-esp.XXXXXX")"
cleanup() { rm -rf "${ESP}"; }
trap cleanup EXIT

mkdir -p "${ESP}/EFI/BOOT"
cp "${EFI_SRC}" "${ESP}/EFI/BOOT/BOOTX64.EFI"
KERN_UEFI="${ROOT}/zig-out/bin/kernel-uefi.elf"
if [[ -f "${KERN_UEFI}" ]]; then
  cp "${KERN_UEFI}" "${ESP}/kernel-uefi.elf"
  cp "${KERN_UEFI}" "${ESP}/KERNEL.ELF"
  echo "已复制 Zig kernel 到 ESP 根（kernel-uefi.elf + KERNEL.ELF）"
fi

OVMF_RESOLVED=""
if [[ -n "${OVMF_CODE:-}" && -f "${OVMF_CODE}" ]]; then
  OVMF_RESOLVED="${OVMF_CODE}"
else
  for p in \
    /usr/share/OVMF/OVMF_CODE.fd \
    /usr/share/qemu/OVMF.fd \
    /usr/share/ovmf/OVMF.fd
  do
    if [[ -f "${p}" ]]; then
      OVMF_RESOLVED="${p}"
      break
    fi
  done
fi

if [[ -z "${OVMF_RESOLVED}" ]]; then
  echo "未找到 OVMF 固件。请安装 ovmf / qemu-efi 包，或设置环境变量 OVMF_CODE 指向 OVMF_CODE.fd。" >&2
  exit 1
fi

echo "OVMF: ${OVMF_RESOLVED}"
echo "ESP:  ${ESP} (qemu fat:rw virtual disk)"

exec qemu-system-x86_64 \
  -machine q35 \
  -m 512M \
  -serial stdio \
  -net none \
  -bios "${OVMF_RESOLVED}" \
  -drive "file=fat:rw:${ESP},format=raw,if=ide,index=0,media=disk"
