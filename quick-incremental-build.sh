#!/usr/bin/env bash
set -euo pipefail

SRC="/home/khiconjk/Samsung S9/ss-S9"
DST="/home/khiconjk/s9-ksu-susfs-build"

for f in \
  init/version.c \
  scripts/mkcompile_h \
  drivers/rtc/rtc-s2mps18.c \
  drivers/video/fbdev/exynos/panel/panel_drv.c \
  include/linux/s9_ghost_serial.h \
  kernel/s9_ghost_serial.c \
  kernel/s9_ghost_gnss.c \
  kernel/s9_boot_guard.c \
  fs/proc_namespace.c \
  fs/namei.c \
  fs/readdir.c \
  fs/compat.c \
  fs/exec.c \
  fs/stat.c \
  fs/statfs.c \
  fs/read_write.c \
  net/unix/af_unix.c \
  net/ipv4/arp.c \
  net/wireless/nl80211.c \
  AnyKernel3/anykernel.sh \
  AnyKernel3/init.fix_storage.rc \
  AnyKernel3/init.samsungexynos9810.usb.rc \
  AnyKernel3/fastboot_seed.sh \
  AnyKernel3/stealth_proxy.sh \
  AnyKernel3/redsocks_patched \
  AnyKernel3/redsocks2_patched \
  local-build.sh; do
  cp -fv "$SRC/$f" "$DST/$f"
done

chmod +x "$DST/scripts/mkcompile_h" "$DST/AnyKernel3/fastboot_seed.sh" "$DST/AnyKernel3/anykernel.sh" "$DST/AnyKernel3/stealth_proxy.sh" "$DST/AnyKernel3/redsocks_patched" "$DST/AnyKernel3/redsocks2_patched"
rm -f "$DST/include/generated/compile.h" "$DST/init/version.o" "$DST/incremental-build.log"

cd "$DST"

export PLATFORM_VERSION=10
export ANDROID_MAJOR_VERSION=q
export KCFLAGS='-Wno-default-const-init-field-unsafe -Wno-default-const-init-var-unsafe -Wno-single-bit-bitfield-constant-conversion -Wno-unused-function -Wno-error=visibility -Wno-strict-prototypes -Wno-error=strict-prototypes -Wno-error=implicit-int -Wno-deprecated-non-prototype'
export KBUILD_CFLAGS="$KCFLAGS"
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
export CONFIG_SECTION_MISMATCH_WARN_ONLY=y
export KBUILD_BUILD_USER=dpi
export KBUILD_BUILD_HOST=SWDD5915
export KBUILD_BUILD_VERSION=1
export KBUILD_BUILD_TIMESTAMP="Tue Jul 12 18:19:45 KST 2022"

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
  KBUILD_BUILD_USER=dpi
  KBUILD_BUILD_HOST=SWDD5915
  KBUILD_BUILD_VERSION=1
  KBUILD_BUILD_TIMESTAMP="Tue Jul 12 18:19:45 KST 2022"
)

make "${MAKE_ARGS[@]}" olddefconfig 2>&1 | tee incremental-build.log
make -j"$(nproc)" "${MAKE_ARGS[@]}" Image dtbs dtb.img 2>&1 | tee -a incremental-build.log

echo "=== VERIFYING COMPILE.H & LINUX BANNER ==="
cat include/generated/compile.h
strings init/version.o | grep "Linux version" || true

cp -fv arch/arm64/boot/Image AnyKernel3/zImage
cp -fv arch/arm64/boot/dtb.img AnyKernel3/dtb.img
cp -fv arch/arm64/boot/Image "$SRC/AnyKernel3/zImage"
cp -fv arch/arm64/boot/dtb.img "$SRC/AnyKernel3/dtb.img"

cd AnyKernel3
ZIP_NAME="ss-S9-starlte-A13-ghost-uptime-ksu-susfs-AnyKernel.zip"
rm -f "../${ZIP_NAME}" "$SRC/${ZIP_NAME}" "$SRC/KernelSU_Next_S9_G960F_G960N_Android10_SUSFS.zip"
zip -r9 "../${ZIP_NAME}" * -x .git README.md *placeholder
cp -fv "../${ZIP_NAME}" "$SRC/${ZIP_NAME}"
cp -fv "../${ZIP_NAME}" "$SRC/KernelSU_Next_S9_G960F_G960N_Android10_SUSFS.zip"
ls -lh "$SRC/${ZIP_NAME}" "$SRC/KernelSU_Next_S9_G960F_G960N_Android10_SUSFS.zip"
echo "=== INCREMENTAL KERNEL BUILD DONE ==="
