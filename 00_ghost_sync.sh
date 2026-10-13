#!/system/bin/sh
# 00_ghost_sync.sh - Pre-Zygote identity sync via ksud resetprop
CONF=""
for p in /efs/ghost.conf /mnt/vendor/efs/ghost.conf /data/system/ghost.conf.bak; do
    if [ -s "$p" ]; then
        CONF="$p"
        break
    fi
done

if [ -n "$CONF" ] && [ -x /data/adb/ksud ]; then
    /data/adb/ksud resetprop -n -f "$CONF" 2>/dev/null
fi

if [ -x /system/bin/ghost_sync.sh ]; then
    /system/bin/sh /system/bin/ghost_sync.sh 2>/dev/null
fi
