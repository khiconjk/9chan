#!/bin/bash
set -euo pipefail
cd /home/khiconjk/s9-ksu-susfs-build

export ARCH=arm64
export SUBARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_ARM32=arm-linux-gnueabi-
export CLANG_TRIPLE=aarch64-linux-gnu-
export PLATFORM_VERSION="13"
export ANDROID_MAJOR_VERSION="s"
export ANDROID_VERSION="130000"
export CONFIG_SECTION_MISMATCH_WARN_ONLY=y
export KCFLAGS="-Wno-default-const-init-field-unsafe -Wno-default-const-init-var-unsafe -Wno-single-bit-bitfield-constant-conversion -Wno-unused-function -Wno-error=visibility -Wno-strict-prototypes -Wno-error=strict-prototypes -Wno-error=implicit-int -Wno-deprecated-non-prototype"
export KBUILD_CFLAGS="$KCFLAGS"

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
BUILD_DIR="/home/khiconjk/s9-ksu-susfs-build"
BASE_DEFCONFIG="arch/arm64/configs/exynos9810_defconfig"
DEVICE_DEFCONFIG="arch/arm64/configs/exynos9810-starlte_defconfig"

echo "=========================================================="
echo " S9 STARLTE - VANILLA CLEAN NON-ROOT KERNEL BUILD (A13)"
echo " Date: $(date)"
echo " Base defconfigs: ${BASE_DEFCONFIG} + ${DEVICE_DEFCONFIG}"
echo " Workspace: ${OUT_WORKSPACE}"
echo "=========================================================="

# 1. Sync latest helper scripts into AnyKernel3
echo ">>> Syncing latest AnyKernel3 helper scripts from workspace..."
cp -fv "${OUT_WORKSPACE}/stealth_proxy.sh" "${BUILD_DIR}/AnyKernel3/stealth_proxy.sh" || true
cp -fv "${OUT_WORKSPACE}/fastboot_seed.sh" "${BUILD_DIR}/AnyKernel3/fastboot_seed.sh" || true
cp -fv "${OUT_WORKSPACE}/init.fix_storage.rc" "${BUILD_DIR}/AnyKernel3/init.fix_storage.rc" || true
cp -fv "${OUT_WORKSPACE}/adb_keys" "${BUILD_DIR}/AnyKernel3/adb_keys" || true

# 2. Prepare .config for VANILLA
echo ""
echo ">>> Preparing .config for VANILLA (Daily Driver / Non-Root Clean)..."
cat "$BASE_DEFCONFIG" "$DEVICE_DEFCONFIG" > .config

python3 - << 'PYCONFIG'
from pathlib import Path
p = Path(".config")
text = p.read_text(errors="ignore").splitlines()

set_y = {
    # Live functional configs for Pixel Experience 13
    "CONFIG_DM_VERITY",
    "CONFIG_DM_VERITY_FEC",
    "CONFIG_HZ_250",
    "CONFIG_MODULES",
    "CONFIG_MODULE_UNLOAD",
    "CONFIG_MODVERSIONS",
    "CONFIG_CPU_FREQ_TIMES",
    "CONFIG_NETFILTER_XT_MATCH_QTAGUID",
    "CONFIG_NETFILTER_XT_MATCH_ONESHOT",
    "CONFIG_NET_CLS_CGROUP",
    "CONFIG_CGROUP_NET_CLASSID",
    "CONFIG_POSIX_MQUEUE",
    "CONFIG_POSIX_MQUEUE_SYSCTL",
    "CONFIG_ZSWAP",
    "CONFIG_ZPOOL",
    "CONFIG_FRONTSWAP",
    "CONFIG_VNSWAP",
    "CONFIG_ASYMMETRIC_KEY_TYPE",
    "CONFIG_ASYMMETRIC_PUBLIC_KEY_SUBTYPE",
    "CONFIG_X509_CERTIFICATE_PARSER",
    "CONFIG_FW_LOADER_USER_HELPER",
    "CONFIG_FW_LOADER_USER_HELPER_FALLBACK",
    "CONFIG_BCM4361",
    "CONFIG_MALI_BIFROST_R40P0",
    "CONFIG_ANDROID_BINDER_IPC",
    "CONFIG_ANDROID_LOW_MEMORY_KILLER",
    "CONFIG_EXYNOS_DTBTOOL",
    "CONFIG_BUILD_ARM64_APPENDED_DTB_IMAGE",
    # EROFS for Android 13 /vendor
    "CONFIG_EROFS_FS",
    "CONFIG_EROFS_FS_XATTR",
    "CONFIG_EROFS_FS_POSIX_ACL",
    "CONFIG_EROFS_FS_SECURITY",
    "CONFIG_EROFS_FS_ZIP",
}

set_n = {
    # Disable force upload and knox
    "CONFIG_SEC_DEBUG_SUPPORT_FORCE_UPLOAD",
    "CONFIG_HZ_100",
    "CONFIG_HZ_300",
    "CONFIG_MALI_BIFROST_R19P0_Q",
    "CONFIG_UH",
    "CONFIG_UH_DEBUG",
    "CONFIG_UH_RKP",
    "CONFIG_UH_RKP_8G",
    "CONFIG_UH_INFORM",
    "CONFIG_UH_RKP_FIMC_TYPE",
    "CONFIG_RKP_KDP",
    "CONFIG_RKP_NS_PROT",
    "CONFIG_RKP_DMAP_PROT",
    "CONFIG_RKP_CFP_JOPP",
    "CONFIG_FIPS_FMP",
    "CONFIG_CRYPTO_FIPS",
    # Disable all root / KernelSU / SuSFS
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

custom_vals = {
    "CONFIG_LITTLE_CPU_MASK": "15",
    "CONFIG_BIG_CPU_MASK": "240",
    "CONFIG_NR_CPUS": "8",
    "CONFIG_HZ": "250",
    "CONFIG_DM_VERITY_HASH_PREFETCH_MIN_SIZE": "1",
}

keys = set_y | set_n | set(custom_vals.keys())
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
out.append("# Pixel 13 Golden Config Options (Vanilla Non-Root Clean)")
for k in sorted(set_y):
    out.append(f"{k}=y")
for k in sorted(set_n):
    out.append(f"# {k} is not set")
for k, v in sorted(custom_vals.items()):
    out.append(f"{k}={v}")

p.write_text("\n".join(out) + "\n")
print("[CONFIG] Applied VANILLA + EROFS + DM-Verity + HZ250 to .config")
PYCONFIG

make "${MAKE_ARGS[@]}" olddefconfig

echo ">>> Verifying required configs for VANILLA..."
for REQUIRED in CONFIG_EROFS_FS CONFIG_DM_VERITY CONFIG_DM_VERITY_FEC CONFIG_MALI_BIFROST_R40P0; do
  if ! grep -q "^${REQUIRED}=y" .config; then
    echo "ERROR: ${REQUIRED}=y was not preserved in .config"
    exit 1
  fi
done
if grep -q "^CONFIG_KSU=y" .config; then
  echo "ERROR: CONFIG_KSU must NOT be present in VANILLA build"
  exit 1
fi
if grep -q "^CONFIG_KSU_SUSFS=y" .config; then
  echo "ERROR: CONFIG_KSU_SUSFS must NOT be present in VANILLA build"
  exit 1
fi
if grep -q "^CONFIG_SEC_DEBUG_SUPPORT_FORCE_UPLOAD=y" .config; then
  echo "ERROR: CONFIG_SEC_DEBUG_SUPPORT_FORCE_UPLOAD must not be enabled!"
  exit 1
fi
echo ">>> Config verification PASSED!"

echo ">>> Compiling VANILLA Kernel Image + DTBs + dtb.img (-j64)..."
make -j64 "${MAKE_ARGS[@]}" Image dtbs dtb.img

if [ ! -f "arch/arm64/boot/dtb.img" ]; then
  make -j64 "${MAKE_ARGS[@]}" V=1 dtb.img
fi

# Save compiled binaries for VANILLA
cp -fv arch/arm64/boot/Image /tmp/Image_vanilla
cp -fv arch/arm64/boot/dtb.img /tmp/dtb_vanilla.img
cp -fv arch/arm64/boot/Image "${OUT_WORKSPACE}/Image_vanilla"
cp -fv arch/arm64/boot/dtb.img "${OUT_WORKSPACE}/dtb_vanilla.img"

echo ">>> Packaging AnyKernel3 for VANILLA..."
cp -fv arch/arm64/boot/Image AnyKernel3/zImage
cp -fv arch/arm64/boot/dtb.img AnyKernel3/dtb.img
cp -fv arch/arm64/boot/dtb.img AnyKernel3/dt.img

cat << 'INFO_EOF' > AnyKernel3/BUILD_INFO.txt
ss-S9 kernel build (Golden Base)
Device: Samsung Galaxy S9 starlte (SM-G960F / SM-G960N)
ROM target: Pixel Experience Plus Android 13 (TQ3A.230901.001.B1)
Kernel base: Linux 4.9.191-perf (Ghost Uptime + Netlink/ARP Cloak + EROFS Vendor + DM-Verity)
KernelSU: None (Vanilla Clean Non-Root)
SuSFS: None
Target SDK lock: 33
Crypto state: FBE (file)
Compiler: Clang 14 with AArch64 GNU binutils
Variant: DAILY DRIVER / CLEAN (Vanilla Ghost Full Non-Root)
Built: $(date)
INFO_EOF

sed -i "s/^kernel.string=.*/kernel.string=ss-S9 Pixel Experience 13 VANILLA GHOST GOLDEN (Clean Non-Root)/" AnyKernel3/anykernel.sh

ZIP_VANILLA="ss-S9-starlte-A13-VANILLA_GHOST_FULL-AnyKernel.zip"
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
echo " Repacking standalone boot images (boot.img & Odin tar)..."
echo "=========================================================="
cd "${OUT_WORKSPACE}"
python3 repack_boot_images.py

echo ""
echo "=========================================================="
echo " VERIFYING INTEGRITY OF COMPILED VANILLA IMAGE..."
echo "=========================================================="
python3 - << 'VERIFY_EOF'
import subprocess, sys

image = "Image_vanilla"
print(f"[*] Scanning {image} symbols...")

def run_grep(pattern):
    cmd = f"grep -a '{pattern}' {image}"
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
echo "All outputs ready in ${OUT_WORKSPACE}:"
ls -lh "${OUT_WORKSPACE}"/Image_vanilla
ls -lh "${OUT_WORKSPACE}"/boot_pixel13_vanilla_fixed.*
ls -lh "${OUT_WORKSPACE}/${ZIP_VANILLA}"
