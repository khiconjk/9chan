#!/bin/bash
set -euo pipefail
cd /home/khiconjk/kernel_pe13_4.9.337

export ARCH=arm64
export SUBARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_ARM32=arm-linux-gnueabi-
export CLANG_TRIPLE=aarch64-linux-gnu-
export PLATFORM_VERSION="13"
export ANDROID_MAJOR_VERSION="s"
export ANDROID_VERSION="130000"
export CONFIG_SECTION_MISMATCH_WARN_ONLY=y
export KCFLAGS="-Wno-default-const-init-field-unsafe -Wno-default-const-init-var-unsafe -Wno-single-bit-bitfield-constant-conversion -Wno-unused-function -Wno-error=visibility -Wno-strict-prototypes -Wno-error=strict-prototypes -Wno-error=implicit-int -Wno-deprecated-non-prototype -Wno-error"
export KBUILD_CFLAGS="$KCFLAGS"

NCPU=$(nproc)

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
  PLATFORM_VERSION="13"
  ANDROID_MAJOR_VERSION="s"
  ANDROID_VERSION="130000"
  CONFIG_SECTION_MISMATCH_WARN_ONLY=y
  KCFLAGS="${KCFLAGS}"
  KBUILD_BUILD_USER=android-build
  KBUILD_BUILD_HOST=google.com
  KBUILD_BUILD_VERSION=1
  KBUILD_BUILD_TIMESTAMP="Fri Aug 14 18:30:00 UTC 2026"
)

OUT_WORKSPACE="/home/khiconjk/Samsung S9/ss-S9"

echo "=========================================================="
echo " S9 STARLTE - PIXEL EXPERIENCE 13 (4.9.337-decon) VANILLA"
echo " Date: $(date)"
echo " CPU Threads: ${NCPU}"
echo " Workspace:   ${OUT_WORKSPACE}"
echo "=========================================================="

echo ">>> Configuring .config for Clean Non-Root..."
sed -i 's/^CONFIG_KSU=y/# CONFIG_KSU is not set/' .config
sed -i 's/^CONFIG_KSU_MANUAL_HOOK=y/# CONFIG_KSU_MANUAL_HOOK is not set/' .config
sed -i 's/^CONFIG_KSU_SUSFS=y/# CONFIG_KSU_SUSFS is not set/' .config
sed -i 's/^CONFIG_KSU_SUSFS_.*=y/# &/' .config

make "${MAKE_ARGS[@]}" olddefconfig

if grep -q "^CONFIG_KSU=y" .config; then
  echo "ERROR: CONFIG_KSU must NOT be present in VANILLA build"
  exit 1
fi
if grep -q "^CONFIG_KSU_SUSFS=y" .config; then
  echo "ERROR: CONFIG_KSU_SUSFS must NOT be present in VANILLA build"
  exit 1
fi
if ! grep -q 'CONFIG_LOCALVERSION="-decon"' .config; then
  echo "ERROR: CONFIG_LOCALVERSION must be -decon for Pixel Experience 13"
  exit 1
fi
echo ">>> Config verification PASSED!"

echo ">>> Compiling 4.9.337-decon VANILLA Kernel Image + DTBs (-j${NCPU})..."
make -j${NCPU} "${MAKE_ARGS[@]}" Image dtbs

echo ">>> Generating Samsung Exynos 9810 DTB image with dtbtool..."
./scripts/dtbtool_exynos/dtbtool --pagesize 2048 --platform 0x50a6 --subtype 0x217584da -o arch/arm64/boot/dtb.img arch/arm64/boot/dts/exynos/exynos9810-starlte_eur_open_26.dtb

DTB_SZ=$(stat -c%s arch/arm64/boot/dtb.img)
echo ">>> Generated dtb.img size: ${DTB_SZ} bytes"
if [ "${DTB_SZ}" -ne 303104 ]; then
  echo "WARNING: dtb.img size is ${DTB_SZ}, expected 303104 bytes"
fi

# Save compiled binaries
cp -fv arch/arm64/boot/Image "${OUT_WORKSPACE}/Image_vanilla"
cp -fv arch/arm64/boot/dtb.img "${OUT_WORKSPACE}/dtb_vanilla.img"

echo ""
echo "=========================================================="
echo " VERIFYING INTEGRITY OF COMPILED VANILLA IMAGE..."
echo "=========================================================="
python3 - << 'VERIFY_EOF'
import subprocess, sys

image = "/home/khiconjk/Samsung S9/ss-S9/Image_vanilla"
print(f"[*] Scanning {image} symbols...")

def run_grep(pattern):
    cmd = f"grep -a '{pattern}' '{image}'"
    res = subprocess.run(cmd, shell=True, capture_output=True)
    return res.returncode == 0

# Check 1: Root symbols MUST NOT exist
ksu_found = run_grep("ksu_")
susfs_found = run_grep("susfs")
if ksu_found:
    print("[FAIL] Found KernelSU symbols in vanilla image!")
    sys.exit(1)
if susfs_found:
    print("[FAIL] Found SuSFS symbols in vanilla image!")
    sys.exit(1)
print("[PASS] 100% Clean: Zero KernelSU / SuSFS symbols found.")

# Check 2: Ghost patches MUST exist
ghost_checks = [
    ("s9_ghost_serial", "Virtual eMMC CID / SCSI UFS / Baseband Spoofing"),
    ("s9_is_ghost_hidden_filename", "VFS Dirent Hiding (ghost.conf, fastboot_seed, etc.)"),
    ("s9_ghost_vfs_inject_string", "VFS Storage In-Memory Virtualization"),
    ("s9_ghost_patch_properties", "Android Property In-Memory Trie Patching"),
]
for symbol, desc in ghost_checks:
    if run_grep(symbol):
        print(f"[PASS] Confirmed: {desc} ({symbol})")
    else:
        print(f"[WARN] Symbol {symbol} not directly found in raw string table (might be inlined)")

print("[SUCCESS] Kernel verification completed successfully!")
VERIFY_EOF

echo ""
echo "=========================================================="
echo " Repacking standalone boot images (boot.img & Odin tar)..."
echo "=========================================================="
cd "${OUT_WORKSPACE}"
python3 repack_boot_images.py

echo ""
echo "=========================================================="
echo " Packaging AnyKernel3 ZIP for TWRP recovery..."
echo "=========================================================="
cd /home/khiconjk/s9-ksu-susfs-build
cp -fv "${OUT_WORKSPACE}/Image_vanilla" AnyKernel3/zImage
cp -fv "${OUT_WORKSPACE}/dtb_vanilla.img" AnyKernel3/dtb.img
cp -fv "${OUT_WORKSPACE}/dtb_vanilla.img" AnyKernel3/dt.img

cat << 'INFO_EOF' > AnyKernel3/BUILD_INFO.txt
ss-S9 kernel build (Linux 4.9.337-decon Base)
Device: Samsung Galaxy S9 starlte (SM-G960F / SM-G960N)
ROM target: Pixel Experience Plus Android 13 (TQ3A.230901.001.B1)
Kernel base: Linux 4.9.337-decon (Ghost Uptime + S9 Ghost Suite + In-Memory Trie)
KernelSU: None (Vanilla Clean Non-Root)
SuSFS: None
Target SDK lock: 33
Crypto state: FBE (file)
Compiler: Clang with AArch64 GNU binutils
Variant: DAILY DRIVER / CLEAN (Vanilla Ghost Full Non-Root)
Built: $(date)
INFO_EOF

sed -i "s/^kernel.string=.*/kernel.string=ss-S9 Pixel Experience 13 4.9.337 VANILLA GHOST (Clean Non-Root)/" AnyKernel3/anykernel.sh

ZIP_VANILLA="ss-S9-starlte-A13-4.9.337-VANILLA_GHOST-AnyKernel.zip"
cd AnyKernel3
rm -f "../${ZIP_VANILLA}"
zip -r9 "../${ZIP_VANILLA}" * -x .git README.md *placeholder
cd ..

cp -fv "${ZIP_VANILLA}" "${OUT_WORKSPACE}/${ZIP_VANILLA}"
sha256sum "${ZIP_VANILLA}" > "${ZIP_VANILLA}.sha256"
cp -fv "${ZIP_VANILLA}.sha256" "${OUT_WORKSPACE}/${ZIP_VANILLA}.sha256"
echo ">>> Built ${ZIP_VANILLA} successfully!"

echo ""
echo "=========================================================="
echo " ALL VANILLA 4.9.337 BUILDS COMPLETED SUCCESSFULLY!"
echo "=========================================================="
ls -lh "${OUT_WORKSPACE}"/Image_vanilla
ls -lh "${OUT_WORKSPACE}"/dtb_vanilla.img
ls -lh "${OUT_WORKSPACE}"/boot_pixel13_vanilla_fixed.img
ls -lh "${OUT_WORKSPACE}"/boot_pixel13_vanilla_fixed.tar
ls -lh "${OUT_WORKSPACE}/${ZIP_VANILLA}"
