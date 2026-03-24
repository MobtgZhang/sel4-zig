#!/usr/bin/env bash
# 阶段 F：OVMF + FAT ESP，含 BOOTX64.EFI 与 kernel-uefi.elf，串口关键字断言。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EFI_SRC="${ROOT}/zig-out/bin/BOOTX64.efi"
KERN_SRC="${ROOT}/zig-out/bin/kernel-uefi.elf"

for f in "${EFI_SRC}" "${KERN_SRC}"; do
  if [[ ! -f "${f}" ]]; then
    echo "找不到 ${f}，请先: cd ${ROOT} && zig build" >&2
    exit 1
  fi
done

ESP="$(mktemp -d "${TMPDIR:-/tmp}/sel4-zig-esp.XXXXXX")"
OUT="$(mktemp)"
cleanup() { rm -rf "${ESP}"; rm -f "${OUT}"; }
trap cleanup EXIT

mkdir -p "${ESP}/EFI/BOOT"
cp "${EFI_SRC}" "${ESP}/EFI/BOOT/BOOTX64.EFI"
cp "${KERN_SRC}" "${ESP}/kernel-uefi.elf"
cp "${KERN_SRC}" "${ESP}/KERNEL.ELF"
cp "${KERN_SRC}" "${ESP}/EFI/BOOT/KERN.ELF"

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
  echo "未找到 OVMF 固件" >&2
  exit 1
fi

set +e
timeout 35 qemu-system-x86_64 \
  -machine q35 \
  -m 512M \
  -serial file:"${OUT}" \
  -display none \
  -nographic \
  -net none \
  -bios "${OVMF_RESOLVED}" \
  -drive "file=fat:rw:${ESP},format=raw,if=ide,index=0,media=disk" \
  -no-reboot \
  -no-shutdown
set -e

if grep -q "kernelInit" "${OUT}"; then
  echo "verify-kernel-handoff: OK (found kernelInit)"
  exit 0
fi
echo "verify-kernel-handoff: 失败，串口输出片段：" >&2
tail -c 4096 "${OUT}" | tr -d '\0' | tail -n 40 >&2
exit 1
