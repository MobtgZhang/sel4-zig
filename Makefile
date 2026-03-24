# seL4-Zig —— 阶段二 UEFI + 阶段三/四 内核迁移实验工程
#
# 用法:
#   make              构建 BOOTX64.efi
#   make test         主机上 Zig 迁移测试
#   make qemu         QEMU+OVMF 仅 UEFI
#   make verify-uefi  阶段六：-nographic + 串口（idea1.md 6.1）
#   make run          QEMU+OVMF，ESP 含 BOOTX64.EFI 与 boot/kernel.elf（需已有 kernel.elf，见 README）
#
# 变量:
#   SEL4_DIR   官方 seL4（C/CMake）根目录，默认与本仓库并列的 ../seL4，供脚本与对照构建
#   ZIG        zig 可执行文件

SEL4_ZIG_ROOT := $(abspath .)
SEL4_DIR      ?= $(abspath $(SEL4_ZIG_ROOT)/../seL4)
SEL4_BUILD    ?= $(SEL4_DIR)/build-sel4-zig
ZIG           ?= zig

.PHONY: all uefi test qemu verify-uefi verify-kernel-handoff kernel-qemu kernel-qemu-direct kernel-qemu-aarch64 kernel-qemu-riscv64 kernel-qemu-loongarch64 sel4-codegen run clean help sync-vendor gen-manifest

all: uefi

uefi:
	$(ZIG) build

test:
	$(ZIG) build test

qemu:
	$(ZIG) build qemu

verify-uefi:
	$(ZIG) build verify-uefi

kernel-qemu:
	$(ZIG) build kernel-qemu

kernel-qemu-direct:
	$(ZIG) build kernel-qemu-direct

kernel-qemu-aarch64:
	$(ZIG) build kernel-qemu-aarch64

kernel-qemu-riscv64:
	$(ZIG) build kernel-qemu-riscv64

kernel-qemu-loongarch64:
	$(ZIG) build kernel-qemu-loongarch64

verify-kernel-handoff:
	$(ZIG) build verify-kernel-handoff

sel4-codegen:
	$(ZIG) build sel4-codegen

run: uefi
	SEL4_BUILD="$(SEL4_BUILD)" bash "$(SEL4_ZIG_ROOT)/scripts/run-uefi-kernel.sh"

clean:
	rm -rf zig-out .zig-cache $(SEL4_ZIG_ROOT)/.zig-cache

sync-vendor:
	SEL4_DIR="$(SEL4_DIR)" bash "$(SEL4_ZIG_ROOT)/scripts/sync-vendor-from-upstream.sh"

gen-manifest:
	python3 $(SEL4_ZIG_ROOT)/tools/gen_vendor_manifest.py

help:
	@echo "Targets:"
	@echo "  all / uefi     zig build  -> zig-out/bin/BOOTX64.efi"
	@echo "  test           zig build test（阶段三/四 Zig 模块）"
	@echo "  qemu           zig build qemu（仅 UEFI）"
	@echo "  verify-uefi    zig build verify-uefi（-nographic，阶段六）"
	@echo "  kernel-qemu         zig build kernel-qemu（本仓库 Zig kernel.elf + GRUB）"
	@echo "  kernel-qemu-direct  zig build kernel-qemu-direct（qemu -kernel + PVH）"
	@echo "  kernel-qemu-aarch64 / riscv64 / loongarch64  多架构裸内核 QEMU"
	@echo "  verify-kernel-handoff zig build verify-kernel-handoff（UEFI→kernel-uefi.elf）"
	@echo "  sel4-codegen      SEL4_BUILD 指向官方 build 目录时复制 generated/"
	@echo "  run            UEFI + ESP 中的 boot/kernel.elf（默认 SEL4_BUILD 下 kernel.elf）"
	@echo "  sync-vendor    默认仅刷新空清单；FULL_VENDOR_MIRROR=1 时从 \$$(SEL4_DIR) 同步 vendor"
	@echo "  gen-manifest   重新生成 mirror_manifest / 模块目录"
	@echo "  clean          删除 zig 构建缓存与输出"
	@echo ""
	@echo "对照/引导用内核：在 \$$(SEL4_DIR)（默认并列 ../seL4）内按官方 CMake 构建；本仓库以 Zig 迁移为主。"
	@echo "SEL4_DIR=$(SEL4_DIR)  SEL4_BUILD=$(SEL4_BUILD)"
