#!/system/bin/sh
# S9 Ghost Identity Sync Engine v2.2 (Android 13 OneUI 5)
# Zero-Root, Precision Regex & Full Partition RAM/Disk Synchronization

CONF=""
for p in /efs/ghost.conf /mnt/vendor/efs/ghost.conf /data/system/ghost.conf.bak; do
    if [ -s "$p" ]; then
        CONF="$p"
        break
    fi
done
[ -z "$CONF" ] && exit 0

RESETPROP="/system/bin/resetprop"
[ ! -x "$RESETPROP" ] && RESETPROP="/efs/ksu_backup/resetprop"
[ ! -x "$RESETPROP" ] && RESETPROP="/system/xbin/resetprop"

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
BOOTLOADER=$(grep -E '^ro\.bootloader=' "$CONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
BASEBAND=$(grep -E '^gsm\.version\.baseband=' "$CONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
FLAVOR=$(grep -E '^ro\.build\.flavor=' "$CONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
BUILD_ID=$(grep -E '^ro\.build\.id=' "$CONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
BT_NAME=$(grep -E '^bluetooth\.device\.default_name=' "$CONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
[ -z "$BT_NAME" ] && BT_NAME="$MODEL"

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

if [ -n "$BOOTLOADER" ]; then
    $RESETPROP -n "ro.bootloader" "$BOOTLOADER" 2>/dev/null
    $RESETPROP -n "ro.boot.bootloader" "$BOOTLOADER" 2>/dev/null
    $RESETPROP -n "ro.build.PDA" "$BOOTLOADER" 2>/dev/null
fi

if [ -n "$BASEBAND" ]; then
    $RESETPROP -n "gsm.version.baseband" "$BASEBAND" 2>/dev/null
    $RESETPROP -n "ril.sw_ver" "$BASEBAND" 2>/dev/null
fi

if [ -n "$FLAVOR" ]; then
    $RESETPROP -n "ro.build.flavor" "$FLAVOR" 2>/dev/null
fi

if [ -n "$BUILD_ID" ]; then
    $RESETPROP -n "ro.build.id" "$BUILD_ID" 2>/dev/null
    $RESETPROP -n "ro.build.display.id" "$BUILD_ID" 2>/dev/null
fi

if [ -n "$BT_NAME" ]; then
    $RESETPROP -n "bluetooth.device.default_name" "$BT_NAME" 2>/dev/null
    $RESETPROP -n "net.bt.name" "$BT_NAME" 2>/dev/null
fi

# Reset persist flags to clean state
$RESETPROP -n persist.sys.fflag.override.settings_provider_model false 2>/dev/null

# 3. SettingsProvider Synchronized Update
if [ -n "$MODEL" ]; then
    settings put global device_name "$MODEL" 2>/dev/null
    settings put global wifi_p2p_device_name "$MODEL" 2>/dev/null
fi
if [ -n "$BT_NAME" ]; then
    settings put secure bluetooth_name "$BT_NAME" 2>/dev/null
fi

# 4. Anti-Knox Vault ID
$RESETPROP -n ro.security.vault.id 89cb2abb18affe1 2>/dev/null

# 5. Screen Resolution & Density Override
RES=$(grep -E '^ro\.screen\.resolution=' "$CONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
DPI=$(grep -E '^ro\.sf\.lcd_density=' "$CONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')

if [ -n "$RES" ]; then
    $RESETPROP -n ro.screen.resolution "$RES" 2>/dev/null
    wm size "$RES" 2>/dev/null
fi

if [ -n "$DPI" ]; then
    $RESETPROP -n ro.sf.lcd_density "$DPI" 2>/dev/null
    wm density "$DPI" 2>/dev/null
fi

# 6. Physical Disk Files Synchronization with Strict Line-Anchored Regex
mount -o remount,rw / 2>/dev/null
mount -o remount,rw /vendor 2>/dev/null

sync_prop_file() {
    target_file="$1"
    [ ! -f "$target_file" ] && return

    if [ -n "$MODEL" ]; then
        sed -i -E "s#^ro\.product(\.[a-zA-Z0-9_]+)?\.model=.*#ro.product\1.model=$MODEL#g" "$target_file" 2>/dev/null
        sed -i -E "s#^ro\.product\.model=.*#ro.product.model=$MODEL#g" "$target_file" 2>/dev/null
    fi
    if [ -n "$DEVICE" ]; then
        sed -i -E "s#^ro\.product(\.[a-zA-Z0-9_]+)?\.device=.*#ro.product\1.device=$DEVICE#g" "$target_file" 2>/dev/null
        sed -i -E "s#^ro\.product\.device=.*#ro.product.device=$DEVICE#g" "$target_file" 2>/dev/null
        sed -i -E "s#^ro\.build\.product=.*#ro.build.product=$DEVICE#g" "$target_file" 2>/dev/null
    fi
    if [ -n "$NAME" ]; then
        sed -i -E "s#^ro\.product(\.[a-zA-Z0-9_]+)?\.name=.*#ro.product\1.name=$NAME#g" "$target_file" 2>/dev/null
        sed -i -E "s#^ro\.product\.name=.*#ro.product.name=$NAME#g" "$target_file" 2>/dev/null
    fi
    if [ -n "$FP" ]; then
        sed -i -E "s#^ro(\.[a-zA-Z0-9_]+)?\.build\.fingerprint=.*#ro\1.build.fingerprint=$FP#g" "$target_file" 2>/dev/null
    fi
    if [ -n "$BT_NAME" ]; then
        sed -i -E "s#^bluetooth\.device\.default_name=.*#bluetooth.device.default_name=$BT_NAME#g" "$target_file" 2>/dev/null
    fi
    sed -i "s#Galaxy S9#$BT_NAME#g" "$target_file" 2>/dev/null
    sed -i -E "s#^ro\.vendor\.build\.type=userdebug#ro.vendor.build.type=user#g" "$target_file" 2>/dev/null
    sed -i -E "s#^ro\.build\.type=userdebug#ro.build.type=user#g" "$target_file" 2>/dev/null
}

sync_prop_file "/system/build.prop"
sync_prop_file "/vendor/build.prop"
sync_prop_file "/vendor/odm/etc/build.prop"
sync_prop_file "/vendor/vendor_dlkm/etc/build.prop"

exit 0
