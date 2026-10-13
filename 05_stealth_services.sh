#!/system/bin/sh
# 05_stealth_services.sh - Stealth Services Framework via KernelSU + SuSFS
if [ -f /data/adb/stealth/services.jar ] && [ -f /data/adb/stealth/services.odex ]; then
    mount -o bind /data/adb/stealth/services.jar /system/framework/services.jar
    mount -o bind /data/adb/stealth/services.odex /system/framework/oat/arm64/services.odex
    mount -o bind /data/adb/stealth/services.vdex /system/framework/oat/arm64/services.vdex
    mount -o bind /data/adb/stealth/empty.art /system/framework/oat/arm64/services.art

    if [ -x /data/adb/ksud ]; then
        /data/adb/ksud kernel umount add /system/framework/services.jar 2>/dev/null
        /data/adb/ksud kernel umount add /system/framework/oat/arm64/services.odex 2>/dev/null
        /data/adb/ksud kernel umount add /system/framework/oat/arm64/services.vdex 2>/dev/null
        /data/adb/ksud kernel umount add /system/framework/oat/arm64/services.art 2>/dev/null
        /data/adb/ksud kernel notify-module-mounted 2>/dev/null
    fi
fi
