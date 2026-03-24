#!/usr/bin/env bash
# QEMU + OVMF：FAT ESP 内含 BOOTX64.EFI 与 boot/kernel.elf（供后续 UEFI 加载器读取）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EFI_SRC="${ROOT}/zig-out/bin/BOOTX64.efi"

SEL4_BUILD="${SEL4_BUILD:-${ROOT}/../seL4/build-sel4-zig}"
KERNEL_ELF="${KERNEL_ELF:-${SEL4_BUILD}/kernel.elf}"

if [[ ! -f "${EFI_SRC}" ]]; then
  echo "找不到 ${EFI_SRC}，请在 ${ROOT} 下执行: zig build 或 make uefi" >&2
  exit 1
fi

if [[ ! -f "${KERNEL_ELF}" ]]; then
  echo "找不到内核 ${KERNEL_ELF}" >&2
  echo "请先在官方 seL4 树内构建 kernel.elf（默认并列 ../seL4，官方 CMake），或设置 KERNEL_ELF / SEL4_BUILD。" >&2
  echo "或设置 KERNEL_ELF=/path/to/kernel.elf" >&2
  exit 1
fi

ESP="$(mktemp -d "${TMPDIR:-/tmp}/sel4-zig-esp.XXXXXX")"
cleanup() { rm -rf "${ESP}"; }
trap cleanup EXIT

mkdir -p "${ESP}/EFI/BOOT" "${ESP}/boot"
cp "${EFI_SRC}" "${ESP}/EFI/BOOT/BOOTX64.EFI"
cp "${KERNEL_ELF}" "${ESP}/boot/kernel.elf"

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
  echo "未找到 OVMF 固件。请安装 ovmf / qemu-efi 包，或设置 OVMF_CODE 指向 OVMF_CODE.fd。" >&2
  exit 1
fi

echo "OVMF:   ${OVMF_RESOLVED}"
echo "ESP:    ${ESP}"
echo "Kernel: ${KERNEL_ELF} -> boot/kernel.elf"

exec qemu-system-x86_64 \
  -machine q35 \
  -m 512M \
  -serial stdio \
  -net none \
  -bios "${OVMF_RESOLVED}" \
  -drive "file=fat:rw:${ESP},format=raw,if=ide,index=0,media=disk"
