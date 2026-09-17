set -euo pipefail
cd /home/khiconjk/s9-ksu-susfs-build
export SUSFS_BRANCH=1.4.2-kernel-4.9
export SUSFS_REPO=https://gitlab.com/1392726643/susfs4ksu.git
export PLATFORM_VERSION=12 ANDROID_MAJOR_VERSION=s TEMP_DEFCONFIG=exynos9810_temp_defconfig DEVICE_DEFCONFIG=exynos9810-starlte_defconfig
export KCFLAGS='-Wno-default-const-init-field-unsafe -Wno-default-const-init-var-unsafe -Wno-single-bit-bitfield-constant-conversion -Wno-unused-function -Wno-error=visibility -Wno-strict-prototypes -Wno-error=strict-prototypes -Wno-error=implicit-int -Wno-deprecated-non-prototype'
export KBUILD_CFLAGS='-Wno-default-const-init-field-unsafe -Wno-default-const-init-var-unsafe -Wno-single-bit-bitfield-constant-conversion -Wno-unused-function -Wno-error=visibility -Wno-strict-prototypes -Wno-error=strict-prototypes -Wno-error=implicit-int -Wno-deprecated-non-prototype'
set -eo pipefail

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
export PLATFORM_VERSION="$PLATFORM_VERSION"
export ANDROID_MAJOR_VERSION="$ANDROID_MAJOR_VERSION"
export CONFIG_SECTION_MISMATCH_WARN_ONLY=y
export KBUILD_BUILD_USER=android-build
export KBUILD_BUILD_HOST=google.com
export KBUILD_BUILD_VERSION=1
export KBUILD_BUILD_TIMESTAMP="Fri Aug 14 18:30:00 UTC 2026"

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
  PLATFORM_VERSION="$PLATFORM_VERSION"
  ANDROID_MAJOR_VERSION="$ANDROID_MAJOR_VERSION"
  CONFIG_SECTION_MISMATCH_WARN_ONLY=y
  KCFLAGS="${KCFLAGS}"
  KBUILD_BUILD_USER=android-build
  KBUILD_BUILD_HOST=google.com
  KBUILD_BUILD_VERSION=1
  KBUILD_BUILD_TIMESTAMP="Fri Aug 14 18:30:00 UTC 2026"
)

echo "===== COMPILER TEST ====="
clang --target=aarch64-linux-gnu --prefix=/usr/bin/aarch64-linux-gnu- -no-integrated-as -x c -c /dev/null -o /tmp/clang-arm64-test.o
file /tmp/clang-arm64-test.o

BASE_DEFCONFIG="arch/arm64/configs/exynos9810_defconfig"
DEVICE_DEFCONFIG_PATH="arch/arm64/configs/$DEVICE_DEFCONFIG"
TEMP_DEFCONFIG_PATH="arch/arm64/configs/$TEMP_DEFCONFIG"

if [ ! -f "$BASE_DEFCONFIG" ]; then
  echo "ERROR: Missing $BASE_DEFCONFIG"
  exit 1
fi
if [ ! -f "$DEVICE_DEFCONFIG_PATH" ]; then
  echo "ERROR: Missing $DEVICE_DEFCONFIG_PATH"
  exit 1
fi

cat "$BASE_DEFCONFIG" "$DEVICE_DEFCONFIG_PATH" > "$TEMP_DEFCONFIG_PATH"
{
  echo "# v113 stock Android 10 safety config additions"
  echo "CONFIG_ANDROID=y"
  echo "CONFIG_ANDROID_BINDER_IPC=y"
  echo "CONFIG_ANDROID_LOW_MEMORY_KILLER=y"
  echo "CONFIG_EXYNOS_DTBTOOL=y"
  echo "CONFIG_BUILD_ARM64_APPENDED_DTB_IMAGE=y"
  echo "CONFIG_KSU=y"
  echo "CONFIG_KSU_MANUAL_HOOK=y"
  echo "CONFIG_KSU_SUSFS=y"
  echo "CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y"
  echo "CONFIG_KSU_SUSFS_SUS_PATH=y"
  echo "CONFIG_KSU_SUSFS_SUS_MOUNT=y"
  echo "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y"
  echo "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y"
  echo "# CONFIG_KSU_SUSFS_SUS_KSTAT is not set"
  echo "CONFIG_KSU_SUSFS_TRY_UMOUNT=y"
  echo "CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT=y"
  echo "CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y"
  echo "# CONFIG_KSU_DEBUG is not set"
  echo "# CONFIG_KSU_KPROBES_HOOK is not set"
  echo "# CONFIG_KSU_KPROBE_HOOKS is not set"
  echo "# CONFIG_KSU_SUSFS_ENABLE_LOG is not set"
  echo "# CONFIG_KSU_SUSFS_SPOOF_UNAME is not set"
  echo "# CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG is not set"
  echo "# CONFIG_KSU_SUSFS_OPEN_REDIRECT is not set"
  echo "# CONFIG_KSU_SUSFS_SUS_SU is not set"
  echo "CONFIG_BCM4361=y"
} >> "$TEMP_DEFCONFIG_PATH"

echo "===== DEFCONFIG ====="
make "${MAKE_ARGS[@]}" "$TEMP_DEFCONFIG" 2>&1 | tee defconfig.log

echo "===== OLDDEFCONFIG ====="
make "${MAKE_ARGS[@]}" olddefconfig 2>&1 | tee olddefconfig.log

echo "===== HARD REPAIR KSU/SUSFS CONFIG AFTER OLDDEFCONFIG ====="
python3 - <<'PYCONFIG'
from pathlib import Path
p = Path('.config')
text = p.read_text(errors='ignore').splitlines()
set_y = {
    'CONFIG_KSU',
    'CONFIG_KSU_MANUAL_HOOK',
    'CONFIG_KSU_SUSFS',
    'CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT',
    'CONFIG_KSU_SUSFS_SUS_PATH',
    'CONFIG_KSU_SUSFS_SUS_MOUNT',
    'CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT',
    'CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT',
    'CONFIG_KSU_SUSFS_TRY_UMOUNT',
    'CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT',
    'CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS',
}
set_n = {
    'CONFIG_KSU_DEBUG',
    'CONFIG_KSU_DISABLE_MANAGER',
    'CONFIG_KSU_DISABLE_POLICY',
    'CONFIG_KSU_ALLOWLIST_WORKAROUND',
    'CONFIG_KSU_KPROBES_HOOK',
    'CONFIG_KSU_KPROBE_HOOKS',
    'CONFIG_KSU_SUSFS_ENABLE_LOG',
    'CONFIG_KSU_SUSFS_SUS_KSTAT',
    'CONFIG_KSU_SUSFS_SUS_OVERLAYFS',
    'CONFIG_KSU_SUSFS_SPOOF_UNAME',
    'CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG',
    'CONFIG_KSU_SUSFS_OPEN_REDIRECT',
    'CONFIG_KSU_SUSFS_SUS_SU',
}
keys = set_y | set_n
out = []
for line in text:
    stripped = line.strip()
    key = None
    if stripped.startswith('CONFIG_') and '=' in stripped:
        key = stripped.split('=', 1)[0]
    elif stripped.startswith('# CONFIG_') and stripped.endswith(' is not set'):
        key = stripped.split()[1]
    if key in keys:
        continue
    out.append(line)
out.append('')
out.append('# KSU Next + SuSFS hard repair v113 after olddefconfig')
for k in sorted(set_y):
    out.append(f'{k}=y')
for k in sorted(set_n):
    out.append(f'# {k} is not set')
p.write_text('\n'.join(out) + '\n')
print('[PATCH] .config: force-wrote KSU/SuSFS options v113')
PYCONFIG

echo "===== OLDDEFCONFIG AFTER KSU/SUSFS HARD REPAIR ====="
make "${MAKE_ARGS[@]}" olddefconfig 2>&1 | tee -a olddefconfig.log

echo "===== VERIFY REQUIRED KSU/SUSFS CONFIG ====="
grep -E "CONFIG_KSU|CONFIG_KSU_MANUAL_HOOK|CONFIG_KSU_SUSFS" .config || true
for REQUIRED in CONFIG_KSU CONFIG_KSU_MANUAL_HOOK CONFIG_KSU_SUSFS; do
  if ! grep -q "^${REQUIRED}=y" .config; then
    echo "ERROR: ${REQUIRED}=y was not preserved in .config"
    grep -n "${REQUIRED}" .config || true
    exit 1
  fi
done

echo "===== CONFIG CHECK ====="
grep -E "CONFIG_SOC_EXYNOS9810|CONFIG_CAMERA_STAR|CONFIG_CAMERA_STAR2|CONFIG_CAMERA_CROWN|CONFIG_EXYNOS_DTBTOOL|CONFIG_BUILD_ARM64_APPENDED|CONFIG_MODULES|CONFIG_ANDROID|CONFIG_ANDROID_BINDER|CONFIG_ANDROID_LOW_MEMORY_KILLER|CONFIG_KSU|CONFIG_KSU_MANUAL_HOOK|CONFIG_KSU_SUSFS" .config || true

echo "===== BUILD IMAGE + DTBS + DTB.IMG ====="
make -j"64" "${MAKE_ARGS[@]}" Image Image.gz dtbs dtb.img 2>&1 | tee build.log

echo "===== IF dtb.img IS STILL MISSING, TRY dtb.img AGAIN WITH V=1 ====="
if [ ! -f "arch/arm64/boot/dtb.img" ]; then
  make -j"64" "${MAKE_ARGS[@]}" V=1 dtb.img 2>&1 | tee -a build.log
fi

echo "===== OUTPUTS ====="
ls -lah arch/arm64/boot || true
find arch/arm64/boot -maxdepth 8 -type f \( -name "Image*" -o -name "*.dtb" -o -name "dtb.img" -o -name "*.ko" \) -print -exec ls -lh {} \; || true

echo "===== PACKAGING ANYKERNEL3 ====="
cp -fv arch/arm64/boot/Image AnyKernel3/zImage
cp -fv arch/arm64/boot/dtb.img AnyKernel3/dtb.img

cd AnyKernel3
ZIP_NAME="ss-S9-starlte-A13-ghost-uptime-ksu-susfs-AnyKernel.zip"
rm -f "../${ZIP_NAME}"
zip -r9 "../${ZIP_NAME}" * -x .git README.md *placeholder
cd ..
ls -lh "${ZIP_NAME}"
echo "===== BUILD COMPLETED SUCCESSFULLY ====="
