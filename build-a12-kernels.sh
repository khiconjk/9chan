#!/bin/bash
set -euo pipefail
cd /home/khiconjk/s9-ksu-susfs-build

echo "========================================================"
echo " Starting S9 starlte Android 12 Dual Kernel Build"
echo " Target 1: KernelSU Next + SuSFS (Ghost Full)"
echo " Target 2: VANILLA (Ghost Full, Clean / No Root)"
echo "========================================================"

export ARCH=arm64
export SUBARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_ARM32=arm-linux-gnueabi-
export CLANG_TRIPLE=aarch64-linux-gnu-
export CC="clang --target=aarch64-linux-gnu --prefix=/usr/bin/aarch64-linux-gnu- -no-integrated-as"
export HOSTCC=gcc
export HOSTCXX=g++
export AS=aarch64-linux-gnu-as
export LD=aarch64-linux-gnu-ld.bfd
export AR=aarch64-linux-gnu-ar
export NM=aarch64-linux-gnu-nm
export OBJCOPY=aarch64-linux-gnu-objcopy
export OBJDUMP=aarch64-linux-gnu-objdump
export STRIP=aarch64-linux-gnu-strip
export READELF=aarch64-linux-gnu-readelf
export PLATFORM_VERSION=12
export ANDROID_MAJOR_VERSION=s
export CONFIG_SECTION_MISMATCH_WARN_ONLY=y
export KBUILD_BUILD_USER=android-build
export KBUILD_BUILD_HOST=google.com
export KBUILD_BUILD_VERSION=1
export KBUILD_BUILD_TIMESTAMP="Fri Aug 14 18:30:00 UTC 2026"

export KCFLAGS="-Wno-default-const-init-field-unsafe -Wno-default-const-init-var-unsafe -Wno-single-bit-bitfield-constant-conversion -Wno-unused-function -Wno-error=visibility -Wno-strict-prototypes -Wno-error=strict-prototypes -Wno-error=implicit-int -Wno-deprecated-non-prototype"
export KBUILD_CFLAGS="-Wno-default-const-init-field-unsafe -Wno-default-const-init-var-unsafe -Wno-single-bit-bitfield-constant-conversion -Wno-unused-function -Wno-error=visibility -Wno-strict-prototypes -Wno-error=strict-prototypes -Wno-error=implicit-int -Wno-deprecated-non-prototype"

MAKE_ARGS=(
  V=0
  ARCH=arm64
  SUBARCH=arm64
  CROSS_COMPILE=aarch64-linux-gnu-
  CROSS_COMPILE_ARM32=arm-linux-gnueabi-
  CLANG_TRIPLE=aarch64-linux-gnu-
  "CC=clang --target=aarch64-linux-gnu --prefix=/usr/bin/aarch64-linux-gnu- -no-integrated-as"
  HOSTCC=gcc
  HOSTCXX=g++
  AS=aarch64-linux-gnu-as
  LD=aarch64-linux-gnu-ld.bfd
  AR=aarch64-linux-gnu-ar
  NM=aarch64-linux-gnu-nm
  OBJCOPY=aarch64-linux-gnu-objcopy
  OBJDUMP=aarch64-linux-gnu-objdump
  STRIP=aarch64-linux-gnu-strip
  READELF=aarch64-linux-gnu-readelf
  PLATFORM_VERSION="12"
  ANDROID_MAJOR_VERSION="s"
  CONFIG_SECTION_MISMATCH_WARN_ONLY=y
  KCFLAGS="${KCFLAGS}"
  KBUILD_BUILD_USER=android-build
  KBUILD_BUILD_HOST=google.com
  KBUILD_BUILD_VERSION=1
  KBUILD_BUILD_TIMESTAMP="Fri Aug 14 18:30:00 UTC 2026"
)

OUT_WORKSPACE="/home/khiconjk/Samsung S9/ss-S9"
BUILD_DIR="/home/khiconjk/s9-ksu-susfs-build"
BASE_DEFCONFIG="arch/arm64/configs/exynos9810_defconfig"
DEVICE_DEFCONFIG="arch/arm64/configs/exynos9810-starlte_defconfig"
TEMP_DEFCONFIG="exynos9810_temp_defconfig"
TEMP_DEFCONFIG_PATH="arch/arm64/configs/$TEMP_DEFCONFIG"

# -------------------------------------------------------------
# BUILD 1: KernelSU Next + SuSFS (Ghost Full)
# -------------------------------------------------------------
echo ""
echo ">>> [1/2] Preparing defconfig for KSUN_SUSFS..."
cat "$BASE_DEFCONFIG" "$DEVICE_DEFCONFIG" > "$TEMP_DEFCONFIG_PATH"
cat << 'CFG_EOF' >> "$TEMP_DEFCONFIG_PATH"
# Android 12 Pixel Experience + Ghost + KSU Next + SuSFS config
CONFIG_ANDROID=y
CONFIG_ANDROID_BINDER_IPC=y
CONFIG_ANDROID_LOW_MEMORY_KILLER=y
CONFIG_EXYNOS_DTBTOOL=y
CONFIG_BUILD_ARM64_APPENDED_DTB_IMAGE=y
CONFIG_KSU=y
CONFIG_KSU_MANUAL_HOOK=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y
# CONFIG_KSU_SUSFS_SUS_KSTAT is not set
CONFIG_KSU_SUSFS_TRY_UMOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
# CONFIG_KSU_DEBUG is not set
# CONFIG_KSU_KPROBES_HOOK is not set
# CONFIG_KSU_KPROBE_HOOKS is not set
# CONFIG_KSU_SUSFS_ENABLE_LOG is not set
# CONFIG_KSU_SUSFS_SPOOF_UNAME is not set
# CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG is not set
# CONFIG_KSU_SUSFS_OPEN_REDIRECT is not set
# CONFIG_KSU_SUSFS_SUS_SU is not set
CONFIG_BCM4361=y
CFG_EOF

make "${MAKE_ARGS[@]}" "$TEMP_DEFCONFIG"
make "${MAKE_ARGS[@]}" olddefconfig

python3 - << 'PYCONFIG'
from pathlib import Path
p = Path(".config")
text = p.read_text(errors="ignore").splitlines()
set_y = {
    "CONFIG_KSU",
    "CONFIG_KSU_MANUAL_HOOK",
    "CONFIG_KSU_SUSFS",
    "CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT",
    "CONFIG_KSU_SUSFS_SUS_PATH",
    "CONFIG_KSU_SUSFS_SUS_MOUNT",
    "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT",
    "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT",
    "CONFIG_KSU_SUSFS_TRY_UMOUNT",
    "CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT",
    "CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS",
}
set_n = {
    "CONFIG_KSU_DEBUG",
    "CONFIG_KSU_DISABLE_MANAGER",
    "CONFIG_KSU_DISABLE_POLICY",
    "CONFIG_KSU_ALLOWLIST_WORKAROUND",
    "CONFIG_KSU_KPROBES_HOOK",
    "CONFIG_KSU_KPROBE_HOOKS",
    "CONFIG_KSU_SUSFS_ENABLE_LOG",
    "CONFIG_KSU_SUSFS_SUS_KSTAT",
    "CONFIG_KSU_SUSFS_SUS_OVERLAYFS",
    "CONFIG_KSU_SUSFS_SPOOF_UNAME",
    "CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG",
    "CONFIG_KSU_SUSFS_OPEN_REDIRECT",
    "CONFIG_KSU_SUSFS_SUS_SU",
}
keys = set_y | set_n
out = []
for line in text:
    stripped = line.strip()
    key = None
    if stripped.startswith("CONFIG_") and "=" in stripped:
        key = stripped.split("=", 1)[0]
    elif stripped.startswith("# CONFIG_") and stripped.endswith(" is not set"):
        key = stripped.split()[1]
    if key in keys:
        continue
    out.append(line)
out.append("")
out.append("# KSU Next + SuSFS hard repair for A12")
for k in sorted(set_y):
    out.append(f"{k}=y")
for k in sorted(set_n):
    out.append(f"# {k} is not set")
p.write_text("\n".join(out) + "\n")
print("[PATCH] .config: force-wrote KSU Next + SuSFS options")
PYCONFIG

make "${MAKE_ARGS[@]}" olddefconfig

echo ">>> Verifying KSU / SuSFS config..."
for REQUIRED in CONFIG_KSU CONFIG_KSU_MANUAL_HOOK CONFIG_KSU_SUSFS; do
  if ! grep -q "^${REQUIRED}=y" .config; then
    echo "ERROR: ${REQUIRED}=y was not preserved in .config"
    exit 1
  fi
done

echo ">>> Compiling KSUN_SUSFS Kernel Image + DTBs + dtb.img (-j64)..."
make -j64 "${MAKE_ARGS[@]}" Image dtbs dtb.img

if [ ! -f "arch/arm64/boot/dtb.img" ]; then
  make -j64 "${MAKE_ARGS[@]}" V=1 dtb.img
fi

echo ">>> Packaging AnyKernel3 for KSUN_SUSFS..."
cp -fv arch/arm64/boot/Image AnyKernel3/zImage
cp -fv arch/arm64/boot/dtb.img AnyKernel3/dtb.img

cat << 'INFO_EOF' > AnyKernel3/BUILD_INFO.txt
ss-S9 kernel build
Device: Samsung Galaxy S9 starlte / SM-G960N or SM-G960F
ROM target: Pixel Experience Android 12
Kernel base: Linux 4.9 (Ghost Uptime + Headless)
KernelSU: KernelSU Next legacy
SuSFS: 1.4.2-kernel-4.9
Target SDK lock: 32
Compiler: Clang with AArch64 GNU binutils
INFO_EOF

sed -i "s/^kernel.string=.*/kernel.string=ss-S9 Pixel Experience Android 12 Ghost Uptime + KSU Next + SuSFS/" AnyKernel3/anykernel.sh

ZIP_KSU="ss-S9-starlte-A12-KSUN_SUSFS_GHOST_FULL-AnyKernel.zip"
cd AnyKernel3
rm -f "../${ZIP_KSU}"
zip -r9 "../${ZIP_KSU}" * -x .git README.md *placeholder
cd ..

cp -fv "${ZIP_KSU}" "${OUT_WORKSPACE}/${ZIP_KSU}"
sha256sum "${ZIP_KSU}" > "${ZIP_KSU}.sha256"
cp -fv "${ZIP_KSU}.sha256" "${OUT_WORKSPACE}/${ZIP_KSU}.sha256"
echo ">>> [1/2] Built ${ZIP_KSU} successfully!"

# -------------------------------------------------------------
# BUILD 2: VANILLA (Ghost Full, No Root / Clean)
# -------------------------------------------------------------
echo ""
echo ">>> [2/2] Preparing defconfig for VANILLA..."
cat "$BASE_DEFCONFIG" "$DEVICE_DEFCONFIG" > "$TEMP_DEFCONFIG_PATH"
cat << 'CFG_EOF' >> "$TEMP_DEFCONFIG_PATH"
# Android 12 Pixel Experience + Ghost VANILLA config (No KSU)
CONFIG_ANDROID=y
CONFIG_ANDROID_BINDER_IPC=y
CONFIG_ANDROID_LOW_MEMORY_KILLER=y
CONFIG_EXYNOS_DTBTOOL=y
CONFIG_BUILD_ARM64_APPENDED_DTB_IMAGE=y
# CONFIG_KSU is not set
# CONFIG_KSU_SUSFS is not set
CONFIG_BCM4361=y
CFG_EOF

make "${MAKE_ARGS[@]}" "$TEMP_DEFCONFIG"
make "${MAKE_ARGS[@]}" olddefconfig

python3 - << 'PYCONFIG'
from pathlib import Path
p = Path(".config")
text = p.read_text(errors="ignore").splitlines()
set_n = {
    "CONFIG_KSU",
    "CONFIG_KSU_MANUAL_HOOK",
    "CONFIG_KSU_SUSFS",
    "CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT",
    "CONFIG_KSU_SUSFS_SUS_PATH",
    "CONFIG_KSU_SUSFS_SUS_MOUNT",
    "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT",
    "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT",
    "CONFIG_KSU_SUSFS_TRY_UMOUNT",
    "CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT",
    "CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS",
    "CONFIG_KSU_DEBUG",
    "CONFIG_KSU_DISABLE_MANAGER",
    "CONFIG_KSU_DISABLE_POLICY",
    "CONFIG_KSU_ALLOWLIST_WORKAROUND",
    "CONFIG_KSU_KPROBES_HOOK",
    "CONFIG_KSU_KPROBE_HOOKS",
    "CONFIG_KSU_SUSFS_ENABLE_LOG",
    "CONFIG_KSU_SUSFS_SUS_KSTAT",
    "CONFIG_KSU_SUSFS_SUS_OVERLAYFS",
    "CONFIG_KSU_SUSFS_SPOOF_UNAME",
    "CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG",
    "CONFIG_KSU_SUSFS_OPEN_REDIRECT",
    "CONFIG_KSU_SUSFS_SUS_SU",
}
out = []
for line in text:
    stripped = line.strip()
    key = None
    if stripped.startswith("CONFIG_") and "=" in stripped:
        key = stripped.split("=", 1)[0]
    elif stripped.startswith("# CONFIG_") and stripped.endswith(" is not set"):
        key = stripped.split()[1]
    if key in set_n:
        continue
    out.append(line)
out.append("")
out.append("# VANILLA Clean Kernel - No KSU / No SuSFS")
for k in sorted(set_n):
    out.append(f"# {k} is not set")
p.write_text("\n".join(out) + "\n")
print("[PATCH] .config: force-disabled all KSU / SuSFS options for VANILLA")
PYCONFIG

make "${MAKE_ARGS[@]}" olddefconfig

echo ">>> Verifying KSU is disabled for VANILLA..."
if grep -q "^CONFIG_KSU=y" .config; then
  echo "ERROR: CONFIG_KSU=y is still set in VANILLA .config"
  exit 1
fi

echo ">>> Compiling VANILLA Kernel Image + DTBs + dtb.img (-j64)..."
make -j64 "${MAKE_ARGS[@]}" Image dtbs dtb.img

if [ ! -f "arch/arm64/boot/dtb.img" ]; then
  make -j64 "${MAKE_ARGS[@]}" V=1 dtb.img
fi

echo ">>> Packaging AnyKernel3 for VANILLA..."
cp -fv arch/arm64/boot/Image AnyKernel3/zImage
cp -fv arch/arm64/boot/dtb.img AnyKernel3/dtb.img

cat << 'INFO_EOF' > AnyKernel3/BUILD_INFO.txt
ss-S9 kernel build
Device: Samsung Galaxy S9 starlte / SM-G960N or SM-G960F
ROM target: Pixel Experience Android 12
Kernel base: Linux 4.9 (Ghost Uptime + Headless)
KernelSU: None (VANILLA Clean Kernel)
SuSFS: None
Target SDK lock: 32
Compiler: Clang with AArch64 GNU binutils
INFO_EOF

sed -i "s/^kernel.string=.*/kernel.string=ss-S9 Pixel Experience Android 12 VANILLA GHOST FULL (Ghost Uptime + Headless + Always-On)/" AnyKernel3/anykernel.sh

ZIP_VANILLA="ss-S9-starlte-A12-VANILLA_GHOST_FULL-AnyKernel.zip"
cd AnyKernel3
rm -f "../${ZIP_VANILLA}"
zip -r9 "../${ZIP_VANILLA}" * -x .git README.md *placeholder
cd ..

cp -fv "${ZIP_VANILLA}" "${OUT_WORKSPACE}/${ZIP_VANILLA}"
sha256sum "${ZIP_VANILLA}" > "${ZIP_VANILLA}.sha256"
cp -fv "${ZIP_VANILLA}.sha256" "${OUT_WORKSPACE}/${ZIP_VANILLA}.sha256"
echo ">>> [2/2] Built ${ZIP_VANILLA} successfully!"

echo ""
echo "========================================================"
echo " ALL BUILDS COMPLETED SUCCESSFULLY!"
echo " 1. ${ZIP_KSU} ($(ls -lh "${ZIP_KSU}" | awk '{print $5}'))"
echo " 2. ${ZIP_VANILLA} ($(ls -lh "${ZIP_VANILLA}" | awk '{print $5}'))"
echo "========================================================"
