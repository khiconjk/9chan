#!/usr/bin/env bash
set -e
cd /home/khiconjk/s9-ksu-susfs-build

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
  PLATFORM_VERSION="10"
  ANDROID_MAJOR_VERSION="q"
  ANDROID_VERSION="100000"
  CONFIG_SECTION_MISMATCH_WARN_ONLY=y
  KCFLAGS="${KCFLAGS}"
  KBUILD_BUILD_USER=android-build
  KBUILD_BUILD_HOST=google.com
  KBUILD_BUILD_VERSION=1
  KBUILD_BUILD_TIMESTAMP="Fri Aug 14 18:30:00 UTC 2026"
)

OUT_WORKSPACE="/home/khiconjk/Samsung S9/ss-S9"

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
ROM target: Samsung Stock Android 10 (One UI 2.5)
Kernel base: Linux 4.9 (Ghost Uptime + Headless + All Patches)
KernelSU: None (VANILLA Clean Kernel)
SuSFS: None
Target SDK lock: 29
Compiler: Clang with AArch64 GNU binutils
INFO_EOF

sed -i "s/^kernel.string=.*/kernel.string=ss-S9 Stock Android 10 VANILLA GHOST FULL (Ghost Uptime + Headless + Always-On)/" AnyKernel3/anykernel.sh

ZIP_VANILLA="ss-S9-starlte-A10-STOCK_VANILLA_GHOST_FULL-AnyKernel.zip"
cd AnyKernel3
rm -f "../${ZIP_VANILLA}"
zip -r9 "../${ZIP_VANILLA}" * -x .git README.md *placeholder
cd ..

cp -fv "${ZIP_VANILLA}" "${OUT_WORKSPACE}/${ZIP_VANILLA}"
sha256sum "${ZIP_VANILLA}" > "${ZIP_VANILLA}.sha256"
cp -fv "${ZIP_VANILLA}.sha256" "${OUT_WORKSPACE}/${ZIP_VANILLA}.sha256"
echo ">>> Built ${ZIP_VANILLA} successfully!"
