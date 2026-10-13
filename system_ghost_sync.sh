#!/system/bin/sh
# S9 Ghost Identity Sync Engine (Android 13)

CONF=""
for p in /efs/ghost.conf /mnt/vendor/efs/ghost.conf /data/system/ghost.conf.bak; do
    if [ -s "$p" ]; then
        CONF="$p"
        break
    fi
done
[ -z "$CONF" ] && exit 0

RESETPROP="/system/bin/resetprop"
[ ! -x "$RESETPROP" ] && RESETPROP="/data/adb/ksud resetprop"
[ ! -x "$RESETPROP" ] && RESETPROP="/efs/ksu_backup/ksud resetprop"

# 1. Direct bulk resetprop from ghost.conf
$RESETPROP -n -f "$CONF" 2>/dev/null

# 2. Extract values for all partition properties
MODEL=$(grep -E '^ro\.product\.model=' "$CONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
BRAND=$(grep -E '^ro\.product\.brand=' "$CONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
[ -z "$BRAND" ] && BRAND="samsung"
NAME=$(grep -E '^ro\.product\.name=' "$CONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
DEVICE=$(grep -E '^ro\.product\.device=' "$CONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
FP=$(grep -E '^ro\.build\.fingerprint=' "$CONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
SERIAL=$(grep -E '^(ro\.)?(boot\.)?serial(no)?=' "$CONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')

if [ -n "$MODEL" ]; then
    for part in "" ".system" ".vendor" ".odm" ".system_ext" ".bootimage" ".vendor_dlkm"; do
        $RESETPROP -n "ro.product${part}.model" "$MODEL" 2>/dev/null
    done
    $RESETPROP -n "ro.boot.em.model" "$MODEL" 2>/dev/null
fi

if [ -n "$DEVICE" ]; then
    for part in "" ".system" ".vendor" ".odm" ".system_ext" ".bootimage" ".vendor_dlkm"; do
        $RESETPROP -n "ro.product${part}.device" "$DEVICE" 2>/dev/null
    done
    $RESETPROP -n "ro.build.product" "$DEVICE" 2>/dev/null
fi

if [ -n "$NAME" ]; then
    for part in "" ".system" ".vendor" ".odm" ".system_ext" ".bootimage" ".vendor_dlkm"; do
        $RESETPROP -n "ro.product${part}.name" "$NAME" 2>/dev/null
    done
fi

if [ -n "$BRAND" ]; then
    for part in "" ".system" ".vendor" ".odm" ".system_ext" ".bootimage" ".vendor_dlkm"; do
        $RESETPROP -n "ro.product${part}.brand" "$BRAND" 2>/dev/null
        $RESETPROP -n "ro.product${part}.manufacturer" "$BRAND" 2>/dev/null
    done
fi

if [ -n "$FP" ]; then
    for part in "ro.build.fingerprint" "ro.system.build.fingerprint" "ro.vendor.build.fingerprint" "ro.odm.build.fingerprint" "ro.bootimage.build.fingerprint" "ro.vendor_dlkm.build.fingerprint" "ro.system_ext.build.fingerprint"; do
        $RESETPROP -n "$part" "$FP" 2>/dev/null
    done
fi

if [ -n "$SERIAL" ]; then
    $RESETPROP -n "ro.serialno" "$SERIAL" 2>/dev/null
    $RESETPROP -n "ro.boot.serialno" "$SERIAL" 2>/dev/null
    $RESETPROP -n "ril.serialnumber" "$SERIAL" 2>/dev/null
fi

# 3. Setup /data/adb hierarchy if wiped
if [ ! -d /data/adb/ksu ]; then
    mkdir -p /data/adb/ksu/bin /data/adb/service.d /data/adb/post-fs-data.d 2>/dev/null
    [ -x /system/bin/ksud ] && cp -p /system/bin/ksud /data/adb/ksud 2>/dev/null
    [ -x /system/bin/ksud ] && ln -sf /system/bin/ksud /data/adb/ksu/bin/su 2>/dev/null
    chmod 755 /data/adb/ksud 2>/dev/null
fi

# 4. Anti-Knox Vault ID
$RESETPROP -n ro.security.vault.id 89cb2abb18affe1 2>/dev/null
