#!/bin/bash
set -e
cd /home/khiconjk/s9-ksu-susfs-build
export ARCH=arm64
export ANDROID_VERSION=100000
export ANDROID_MAJOR_VERSION=q
export PLATFORM_VERSION=10
export CONFIG_SECTION_MISMATCH_WARN_ONLY=y

EXTRA_FLAGS="-Wno-default-const-init-field-unsafe -Wno-default-const-init-var-unsafe -Wno-single-bit-bitfield-constant-conversion -Wno-unused-function -Wno-error=visibility -Wno-strict-prototypes -Wno-error=strict-prototypes -Wno-error=implicit-int -Wno-deprecated-non-prototype -Wno-error"

make -j$(nproc) CC=clang CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=/usr/bin/aarch64-linux-gnu- KCFLAGS="$EXTRA_FLAGS" Image
cp -f arch/arm64/boot/Image AnyKernel3/zImage
rm -f AnyKernel3/Image
cd AnyKernel3
rm -f ../ss-S9-starlte-A10-STOCK_VANILLA_GHOST_FULL-AnyKernel.zip
zip -r9 ../ss-S9-starlte-A10-STOCK_VANILLA_GHOST_FULL-AnyKernel.zip * -x .git README.md \*placeholder
ls -lh ../ss-S9-starlte-A10-STOCK_VANILLA_GHOST_FULL-AnyKernel.zip
echo "KERNEL_BUILD_SUCCESS"
