#!/system/bin/sh
# S9 Ghost Identity Sync Engine v2.3 (Android 13 OneUI 5 / KernelSU ksud)
# Zero-Root, Precision Regex & Full Partition RAM/Disk Synchronization

CONF=""
for p in /efs/ghost.conf /mnt/vendor/efs/ghost.conf /data/system/ghost.conf.bak; do
    if [ -s "$p" ]; then
        CONF="$p"
        break
    fi
done
[ -z "$CONF" ] && exit 0

RESETPROP="/data/adb/ksud resetprop"
if [ ! -x /data/adb/ksud ]; then
    RESETPROP="/data/adb/ksu/bin/resetprop"
    [ ! -x "$RESETPROP" ] && RESETPROP="/system/bin/resetprop"
    [ ! -x "$RESETPROP" ] && RESETPROP="/efs/ksu_backup/resetprop"
    [ ! -x "$RESETPROP" ] && RESETPROP="/system/xbin/resetprop"
fi

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
INCREMENTAL=$(grep -E '^ro\.build\.version\.incremental=' "$CONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
BT_NAME=$(grep -E '^bluetooth\.device\.default_name=' "$CONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
[ -z "$BT_NAME" ] && BT_NAME="$MODEL"

if [ -n "$MODEL" ]; then
    for part in "" ".system" ".vendor" ".odm" ".system_ext" ".bootimage" ".vendor_dlkm" ".odm_dlkm"; do
        $RESETPROP -n "ro.product${part}.model" "$MODEL" 2>/dev/null
    done
    $RESETPROP -n "ro.boot.em.model" "$MODEL" 2>/dev/null
fi

if [ -n "$DEVICE" ]; then
    for part in "" ".system" ".vendor" ".odm" ".system_ext" ".bootimage" ".vendor_dlkm" ".odm_dlkm"; do
        $RESETPROP -n "ro.product${part}.device" "$DEVICE" 2>/dev/null
    done
    $RESETPROP -n "ro.build.product" "$DEVICE" 2>/dev/null
fi

if [ -n "$NAME" ]; then
    for part in "" ".system" ".vendor" ".odm" ".system_ext" ".bootimage" ".vendor_dlkm" ".odm_dlkm"; do
        $RESETPROP -n "ro.product${part}.name" "$NAME" 2>/dev/null
    done
fi

if [ -n "$BRAND" ]; then
    for part in "" ".system" ".vendor" ".odm" ".system_ext" ".bootimage" ".vendor_dlkm" ".odm_dlkm"; do
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
    if [ -f /config/usb_gadget/g1/strings/0x409/serialnumber ]; then
        echo -n "$SERIAL" > /config/usb_gadget/g1/strings/0x409/serialnumber 2>/dev/null
    fi
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

PRODUCT_CODE=$(grep -E '^(vendor\.)?ril\.product_code=' "$CONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
if [ -n "$PRODUCT_CODE" ]; then
    $RESETPROP -n "ril.product_code" "$PRODUCT_CODE" 2>/dev/null
    $RESETPROP -n "vendor.ril.product_code" "$PRODUCT_CODE" 2>/dev/null
fi

if [ -n "$FLAVOR" ]; then
    $RESETPROP -n "ro.build.flavor" "$FLAVOR" 2>/dev/null
elif [ -n "$NAME" ]; then
    $RESETPROP -n "ro.build.flavor" "${NAME}-user" 2>/dev/null
fi

if [ -n "$BUILD_ID" ]; then
    $RESETPROP -n "ro.build.id" "$BUILD_ID" 2>/dev/null
    $RESETPROP -n "ro.build.display.id" "$BUILD_ID" 2>/dev/null
fi

if [ -n "$NAME" ] && [ -n "$BUILD_ID" ] && [ -n "$INCREMENTAL" ]; then
    $RESETPROP -n "ro.build.description" "${NAME}-user 13 ${BUILD_ID} ${INCREMENTAL} release-keys" 2>/dev/null
fi

if [ -n "$BT_NAME" ]; then
    $RESETPROP -n "bluetooth.device.default_name" "$BT_NAME" 2>/dev/null
    $RESETPROP -n "net.bt.name" "$BT_NAME" 2>/dev/null
fi

# Enforce REL and standard build tags
$RESETPROP -n ro.build.version.codename REL 2>/dev/null
$RESETPROP -n ro.build.version.release_or_codename 13 2>/dev/null
$RESETPROP -n ro.system.build.version.release_or_codename 13 2>/dev/null
$RESETPROP -n ro.vendor.build.version.release_or_codename 13 2>/dev/null

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

# Synchronize settings XML files directly
for sxml in /data/system/users/0/settings_global.xml /data/system/users/0/settings_secure.xml; do
    if [ -f "$sxml" ]; then
        sed -i "s/Galaxy S9/$MODEL/g" "$sxml" 2>/dev/null
        sed -i "s/Galaxy S9/$MODEL/g" "${sxml}.fallback" 2>/dev/null
        sed -i "s/Galaxy S9/$MODEL/g" "${sxml}.new" 2>/dev/null
    fi
done

# Synchronize Bluetooth adapter hardware configuration
if [ -f /data/misc/bluedroid/bt_config.conf ]; then
    if grep -q 'Name =' /data/misc/bluedroid/bt_config.conf; then
        sed -i "s/Name = .*/Name = $BT_NAME/g" /data/misc/bluedroid/bt_config.conf 2>/dev/null
    else
        sed -i "/\[Adapter\]/a Name = $BT_NAME" /data/misc/bluedroid/bt_config.conf 2>/dev/null
    fi
    cp -f /data/misc/bluedroid/bt_config.conf /data/misc/bluedroid/bt_config.bak 2>/dev/null
    chown bluetooth:bluetooth /data/misc/bluedroid/bt_config.* 2>/dev/null
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

# 5.1. Deep Hardware Sysfs Virtualization (Zero-Trace Sysfs Mount)
mkdir -p /data/local/tmp/.sysfs_ghost 2>/dev/null
chmod 711 /data/local/tmp/.sysfs_ghost 2>/dev/null

# A) Battery Capacity Virtualization (charge_full / batt_capacity_max)
BATT_CAP="4500000"
case "$MODEL" in
    SM-S901*) BATT_CAP="3700000" ;;
    SM-S906*) BATT_CAP="4500000" ;;
    SM-S908*) BATT_CAP="5000000" ;;
    SM-G991*) BATT_CAP="4000000" ;;
    SM-G996*) BATT_CAP="4800000" ;;
    SM-G998*) BATT_CAP="5000000" ;;
    SM-G980*) BATT_CAP="4000000" ;;
    SM-G985*) BATT_CAP="4500000" ;;
    SM-G988*) BATT_CAP="5000000" ;;
    SM-N986*) BATT_CAP="4500000" ;;
    SM-A536*|SM-A546*|SM-A336*|SM-A346*|SM-A256*|SM-A356*) BATT_CAP="5000000" ;;
    SM-M336*|SM-M346*|SM-M546*) BATT_CAP="6000000" ;;
    SM-G960*) BATT_CAP="3000000" ;;
    SM-G965*) BATT_CAP="3500000" ;;
    SM-N960*) BATT_CAP="4000000" ;;
esac

BATT_SYS="/sys/devices/platform/battery/power_supply/battery"
if [ -d "$BATT_SYS" ]; then
    echo "$BATT_CAP" > /data/local/tmp/.sysfs_ghost/charge_full
    chmod 644 /data/local/tmp/.sysfs_ghost/charge_full
    if [ -f "$BATT_SYS/charge_full" ]; then
        umount "$BATT_SYS/charge_full" 2>/dev/null
        mount --bind /data/local/tmp/.sysfs_ghost/charge_full "$BATT_SYS/charge_full" 2>/dev/null
    fi
    # Also virtualize nominal fuel gauge full capacity in mAh
    BATT_MAH=$(( BATT_CAP / 1000 ))
    echo "$BATT_MAH" > /data/local/tmp/.sysfs_ghost/fg_fullcapnom
    chmod 644 /data/local/tmp/.sysfs_ghost/fg_fullcapnom
    if [ -f "$BATT_SYS/fg_fullcapnom" ]; then
        umount "$BATT_SYS/fg_fullcapnom" 2>/dev/null
        mount --bind /data/local/tmp/.sysfs_ghost/fg_fullcapnom "$BATT_SYS/fg_fullcapnom" 2>/dev/null
    fi
fi

# B) SoC Machine Board Virtualization (/sys/devices/soc0/machine)
SOC_MACHINE="Samsung Exynos Mobile Board"
case "$MODEL" in
    SM-S901*|SM-S906*|SM-S908*) SOC_MACHINE="Samsung Rainbow rev01 board based on EXYNOS2200" ;;
    SM-G991*|SM-G996*|SM-G998*) SOC_MACHINE="Samsung Olympus rev01 board based on EXYNOS2100" ;;
    SM-G980*|SM-G985*|SM-G988*) SOC_MACHINE="Samsung Hubble rev01 board based on EXYNOS990" ;;
    SM-N986*) SOC_MACHINE="Samsung Canvas rev01 board based on EXYNOS990" ;;
    SM-A536*|SM-A336*|SM-M336*|SM-M346*) SOC_MACHINE="Samsung S5E8825 board based on EXYNOS1280" ;;
    SM-A546*|SM-A346*|SM-M546*|SM-A356*) SOC_MACHINE="Samsung S5E8835 board based on EXYNOS1380" ;;
    SM-G960*|SM-G965*|SM-N960*) SOC_MACHINE="Samsung Star rev26 board based on EXYNOS9810" ;;
esac

if [ -f /sys/devices/soc0/machine ]; then
    echo "$SOC_MACHINE" > /data/local/tmp/.sysfs_ghost/machine
    chmod 644 /data/local/tmp/.sysfs_ghost/machine
    umount /sys/devices/soc0/machine 2>/dev/null
    mount --bind /data/local/tmp/.sysfs_ghost/machine /sys/devices/soc0/machine 2>/dev/null
fi

# C) Flash Storage UFS Model Virtualization (/sys/block/sda/device/model)
UFS_MODEL="KLUCG2K1EA-B0C1"
case "$MODEL" in
    SM-S901*|SM-S906*|SM-S908*) UFS_MODEL="KM5V8001DM-B424" ;;
    SM-G991*|SM-G996*|SM-G998*) UFS_MODEL="KLUDG4UHDB-B2D1" ;;
    SM-N986*|SM-G980*|SM-G985*) UFS_MODEL="KLUDG8V1EE-B0C1" ;;
    SM-A536*|SM-A546*|SM-M546*) UFS_MODEL="KM2V7001CM-B518" ;;
    *) UFS_MODEL="KLUCG2K1EA-B0C1" ;;
esac

if [ -f /sys/block/sda/device/model ]; then
    echo "$UFS_MODEL" > /data/local/tmp/.sysfs_ghost/ufs_model
    chmod 644 /data/local/tmp/.sysfs_ghost/ufs_model
    umount /sys/block/sda/device/model 2>/dev/null
    mount --bind /data/local/tmp/.sysfs_ghost/ufs_model /sys/block/sda/device/model 2>/dev/null
fi

# D) Flash Storage UFS Capacity Virtualization (/sys/block/sda/size)
FAKE_STORAGE_SECTORS=$(grep -E '^fake_storage_sectors=' "$CONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
if [ -n "$FAKE_STORAGE_SECTORS" ] && [ -f /sys/block/sda/size ]; then
    echo "$FAKE_STORAGE_SECTORS" > /data/local/tmp/.sysfs_ghost/sda_size
    chmod 644 /data/local/tmp/.sysfs_ghost/sda_size
    umount /sys/block/sda/size 2>/dev/null
    mount --bind /data/local/tmp/.sysfs_ghost/sda_size /sys/block/sda/size 2>/dev/null
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
sync_prop_file "/system/system_ext/etc/build.prop"
sync_prop_file "/system/system_dlkm/etc/build.prop"
sync_prop_file "/vendor/build.prop"
sync_prop_file "/vendor/odm/etc/build.prop"
sync_prop_file "/vendor/odm_dlkm/etc/build.prop"
sync_prop_file "/vendor/vendor_dlkm/etc/build.prop"

[ -e /proc/s9_serial ] && echo reload > /proc/s9_serial 2>/dev/null

exit 0
