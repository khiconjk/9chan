#!/system/bin/sh
# 00_ghost_sync.sh - Instant identity sync & SELinux patch before Zygote
for p in /efs/ghost.conf /mnt/vendor/efs/ghost.conf /data/system/ghost.conf.bak; do
    if [ -s "$p" ]; then
        [ -x /data/adb/ksud ] && /data/adb/ksud resetprop -n -f "$p" 2>/dev/null
        break
    fi
done

if [ -e /proc/s9_serial ]; then
    echo reload > /proc/s9_serial 2>/dev/null
fi

# Stop GPS AVC denial flooding instantly
if [ -x /data/adb/ksud ]; then
    /data/adb/ksud sepolicy patch 'allow kernel gps_vendor_data_file dir *' 2>/dev/null
    /data/adb/ksud sepolicy patch 'allow kernel gps_vendor_data_file file *' 2>/dev/null
    /data/adb/ksud sepolicy patch 'allow kernel gps_vendor_data_file fifo_file *' 2>/dev/null
fi

# Allow Zygote, System Server, and Apps access to modules and adb_data_file
if [ -x /data/adb/ksud ]; then
    chmod 755 /data/adb 2>/dev/null
    chcon -R u:object_r:system_file:s0 /data/adb/modules/hma_oss_zygisk 2>/dev/null
    /data/adb/ksud sepolicy patch 'allow system_server adb_data_file dir *' 2>/dev/null
    /data/adb/ksud sepolicy patch 'allow system_server adb_data_file file *' 2>/dev/null
    /data/adb/ksud sepolicy patch 'allow zygote adb_data_file dir *' 2>/dev/null
    /data/adb/ksud sepolicy patch 'allow zygote adb_data_file file *' 2>/dev/null
    /data/adb/ksud sepolicy patch 'allow appdomain adb_data_file dir *' 2>/dev/null
    /data/adb/ksud sepolicy patch 'allow appdomain adb_data_file file *' 2>/dev/null
fi

# Auto-restore su wrapper in /data/local/tmp on every boot
if [ -f /data/adb/su_wrapper.sh ]; then
    cp /data/adb/su_wrapper.sh /data/local/tmp/su 2>/dev/null
    chmod 755 /data/local/tmp/su 2>/dev/null
fi

exit 0
