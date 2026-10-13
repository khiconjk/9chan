#!/system/bin/sh
# 10_stealth_dev_adb.sh - Stealth Developer Options & Identity Harmonization
# Powered by KernelSU Next + SuSFS + ksud resetprop

# 1. Hide Developer Options in SettingsProvider
settings put global development_settings_enabled 0 2>/dev/null
settings put secure development_settings_enabled 0 2>/dev/null
settings put system development_settings_enabled 0 2>/dev/null

# 2. Block userland apps from querying ADB network debug port 5555
iptables -D OUTPUT -p tcp --dport 5555 -m owner --uid-owner 10000:99999 -j REJECT 2>/dev/null
iptables -I OUTPUT -p tcp --dport 5555 -m owner --uid-owner 10000:99999 -j REJECT 2>/dev/null

# 3. Synchronize settings XML files
SETTINGS_GLOBAL="/data/system/users/0/settings_global.xml"
if [ -f "$SETTINGS_GLOBAL" ]; then
    sed -i '/name="development_settings_enabled"/s/value="[^"]*"/value="0"/g; /name="development_settings_enabled"/s/defaultValue="[^"]*"/defaultValue="0"/g' "$SETTINGS_GLOBAL" 2>/dev/null
fi

# 4. Synchronize Model & Names from /efs/ghost.conf
CONF=""
for p in /efs/ghost.conf /mnt/vendor/efs/ghost.conf /data/system/ghost.conf.bak; do
    if [ -s "$p" ]; then
        CONF="$p"
        break
    fi
done

if [ -n "$CONF" ]; then
    MODEL=$(grep -E '^ro\.product\.model=' "$CONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
    DEVICE=$(grep -E '^ro\.product\.device=' "$CONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
    NAME=$(grep -E '^ro\.product\.name=' "$CONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
    FP=$(grep -E '^ro\.build\.fingerprint=' "$CONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')

    if [ -n "$MODEL" ]; then
        settings put global device_name "$MODEL" 2>/dev/null
        settings put secure bluetooth_name "$MODEL" 2>/dev/null
        settings put global wifi_p2p_device_name "$MODEL" 2>/dev/null
        
        # Eliminate Galaxy S9 leaks in settings_secure XML
        SETTINGS_SECURE="/data/system/users/0/settings_secure.xml"
        if [ -f "$SETTINGS_SECURE" ]; then
            sed -i "s/Galaxy S9/$MODEL/g" "$SETTINGS_SECURE" 2>/dev/null
            sed -i "s/Galaxy S9/$MODEL/g" "${SETTINGS_SECURE}.fallback" 2>/dev/null
            sed -i "s/Galaxy S9/$MODEL/g" "${SETTINGS_SECURE}.new" 2>/dev/null
        fi

        # Synchronize Bluetooth adapter config file
        if [ -f /data/misc/bluedroid/bt_config.conf ]; then
            if grep -q 'Name =' /data/misc/bluedroid/bt_config.conf; then
                sed -i "s/Name = .*/Name = $MODEL/g" /data/misc/bluedroid/bt_config.conf 2>/dev/null
            else
                sed -i "/\[Adapter\]/a Name = $MODEL" /data/misc/bluedroid/bt_config.conf 2>/dev/null
            fi
            cp -f /data/misc/bluedroid/bt_config.conf /data/misc/bluedroid/bt_config.bak 2>/dev/null
            chown bluetooth:bluetooth /data/misc/bluedroid/bt_config.* 2>/dev/null
        fi
    fi
fi

# 5. Mask Debug markers & Spoof props via ksud/resetprop
RP=""
for r in /data/adb/ksu/bin/resetprop /data/adb/ksud /system/bin/resetprop; do
    if [ -x "$r" ]; then
        RP="$r"
        break
    fi
done

if [ -n "$RP" ]; then
    # Remove sensitive debug tracking markers
    "$RP" -n -d init.svc_debug_pid.adbd 2>/dev/null
    "$RP" -n -d ro.boottime.adbd 2>/dev/null
    "$RP" -n -d service.adb.root 2>/dev/null
    "$RP" -n -d service.adb.tcp.port 2>/dev/null
    
    # Enforce standard Android security properties
    "$RP" -n ro.debuggable 0 2>/dev/null
    "$RP" -n ro.secure 1 2>/dev/null
    "$RP" -n ro.build.type user 2>/dev/null
    "$RP" -n ro.build.tags release-keys 2>/dev/null
    "$RP" -n ro.adb.secure 1 2>/dev/null

    # Prevent Model/Bluetooth name leaks in props
    if [ -n "$MODEL" ]; then
        for part in "" ".system" ".vendor" ".odm" ".system_ext" ".bootimage" ".vendor_dlkm" ".odm_dlkm"; do
            "$RP" -n "ro.product${part}.model" "$MODEL" 2>/dev/null
        done
        "$RP" -n ro.boot.em.model "$MODEL" 2>/dev/null
        "$RP" -n bluetooth.device.default_name "$MODEL" 2>/dev/null
        "$RP" -n net.bt.name "$MODEL" 2>/dev/null
    fi

    if [ -n "$FP" ]; then
        for part in "" ".system" ".vendor" ".odm" ".system_ext" ".bootimage" ".vendor_dlkm"; do
            "$RP" -n "ro${part}.build.fingerprint" "$FP" 2>/dev/null
        done
    fi

    if [ -n "$DEVICE" ]; then
        for part in "" ".system" ".vendor" ".odm" ".system_ext" ".bootimage" ".vendor_dlkm"; do
            "$RP" -n "ro.product${part}.device" "$DEVICE" 2>/dev/null
        done
        "$RP" -n ro.build.product "$DEVICE" 2>/dev/null
    fi

    if [ -n "$NAME" ]; then
        for part in "" ".system" ".vendor" ".odm" ".system_ext" ".bootimage" ".vendor_dlkm"; do
            "$RP" -n "ro.product${part}.name" "$NAME" 2>/dev/null
        done
    fi

    # Enforce REL and standard build tags
    "$RP" -n ro.build.version.codename REL 2>/dev/null
    "$RP" -n ro.build.version.release_or_codename 13 2>/dev/null
    "$RP" -n ro.system.build.version.release_or_codename 13 2>/dev/null
    "$RP" -n ro.vendor.build.version.release_or_codename 13 2>/dev/null

    # Trigger full ghost sync
    if [ -x /system/bin/ghost_sync.sh ]; then
        /system/bin/sh /system/bin/ghost_sync.sh 2>/dev/null
    fi
fi

# 6. Block Wi-Fi Scanning Leaks & Enforce Authentic Samsung OUI MAC
settings put global wifi_scan_always_enabled 0 2>/dev/null
settings put global ble_scan_always_enabled 0 2>/dev/null
settings put global wifi_scan_throttle_enabled 1 2>/dev/null
settings put global wifi_verbose_logging_enabled 0 2>/dev/null
settings put global wifi_connected_mac_randomization_enabled 0 2>/dev/null

WIFI_STORE="/data/misc/apexdata/com.android.wifi/WifiConfigStore.xml"
if [ -f "$WIFI_STORE" ]; then
    sed -i 's/name="MacRandomizationSetting" value="[123]"/name="MacRandomizationSetting" value="0"/g' "$WIFI_STORE" 2>/dev/null
fi

for pkg in $(pm list packages -3 2>/dev/null | cut -d: -f2); do
    cmd appops set "$pkg" WIFI_SCAN ignore 2>/dev/null
done

# 7. Disable IPv6 to prevent hardware MAC and router MAC leaks
sysctl -w net.ipv6.conf.all.disable_ipv6=1 2>/dev/null
sysctl -w net.ipv6.conf.default.disable_ipv6=1 2>/dev/null
sysctl -w net.ipv6.conf.wlan0.disable_ipv6=1 2>/dev/null
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null
echo 1 > /proc/sys/net/ipv6/conf/default/disable_ipv6 2>/dev/null
echo 1 > /proc/sys/net/ipv6/conf/wlan0/disable_ipv6 2>/dev/null
echo 1 > /proc/sys/net/ipv6/conf/all/addr_gen_mode 2>/dev/null
echo 1 > /proc/sys/net/ipv6/conf/default/addr_gen_mode 2>/dev/null
echo 1 > /proc/sys/net/ipv6/conf/wlan0/addr_gen_mode 2>/dev/null
ip -6 addr flush dev wlan0 2>/dev/null
chmod 0400 /proc/net/if_inet6 2>/dev/null
setprop persist.netd.disable_ipv6 1 2>/dev/null

# 8. Background watchdog: continuously enforce IPv6 disabled & prevent netd EUI-64 generation
nohup sh -c '
    while true; do
        if [ "$(cat /proc/sys/net/ipv6/conf/wlan0/disable_ipv6 2>/dev/null)" != "1" ] || [ -s /proc/net/if_inet6 ]; then
            echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null
            echo 1 > /proc/sys/net/ipv6/conf/default/disable_ipv6 2>/dev/null
            echo 1 > /proc/sys/net/ipv6/conf/wlan0/disable_ipv6 2>/dev/null
            echo 1 > /proc/sys/net/ipv6/conf/all/addr_gen_mode 2>/dev/null
            echo 1 > /proc/sys/net/ipv6/conf/default/addr_gen_mode 2>/dev/null
            echo 1 > /proc/sys/net/ipv6/conf/wlan0/addr_gen_mode 2>/dev/null
            ip -6 addr flush dev wlan0 2>/dev/null
            chmod 0400 /proc/net/if_inet6 2>/dev/null
        fi
        sleep 5
    done
' >/dev/null 2>&1 </dev/null &

exit 0
