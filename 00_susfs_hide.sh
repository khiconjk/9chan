#!/system/bin/sh
# 00_susfs_hide.sh - Hide KSU & ADB artifacts from non-root apps
if [ -x /data/adb/ksud ]; then
    /data/adb/ksud susfs add_sus_path /data/adb 2>/dev/null
    /data/adb/ksud susfs add_sus_path /data/adb/ksud 2>/dev/null
    /data/adb/ksud susfs add_sus_path /data/adb/modules 2>/dev/null
    /data/adb/ksud susfs add_sus_path /data/adb/post-fs-data.d 2>/dev/null
    /data/adb/ksud susfs add_sus_path /data/adb/service.d 2>/dev/null
    /data/adb/ksud susfs add_sus_path /data/adb/s9_proxy 2>/dev/null
fi
