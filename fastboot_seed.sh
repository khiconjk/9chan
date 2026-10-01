#!/system/bin/sh
# Fast First-Boot & Headless Always-On ADB Seed Engine (Runs at post-fs-data & boot_completed as root)
# GHOST_SEED_V2026_10_01_KEYSTORE_FIX

sync_persistent_clock() {
    CUR_EPOCH=$(date +%s 2>/dev/null)
    [ -z "$CUR_EPOCH" ] && return 0
    if [ "$CUR_EPOCH" -lt 1735689600 ]; then
        for rp in /efs/ghost_rtc.epoch /mnt/vendor/efs/ghost_rtc.epoch; do
            if [ -f "$rp" ]; then
                SAVED_EPOCH=$(head -n 1 "$rp" 2>/dev/null | tr -d '\r\n ')
                if [ -n "$SAVED_EPOCH" ] && [ "$SAVED_EPOCH" -ge 1735689600 ] 2>/dev/null; then
                    NEW_EPOCH=$((SAVED_EPOCH + 3))
                    date -u "@${NEW_EPOCH}" 2>/dev/null || date "@${NEW_EPOCH}" 2>/dev/null
                    hwclock -w -u 2>/dev/null || hwclock -w 2>/dev/null
                    break
                fi
            fi
        done
    else
        echo "$CUR_EPOCH" > /efs/ghost_rtc.epoch 2>/dev/null
        chown 0:0 /efs/ghost_rtc.epoch 2>/dev/null
        chmod 0600 /efs/ghost_rtc.epoch 2>/dev/null
        hwclock -w -u 2>/dev/null || hwclock -w 2>/dev/null
    fi
}

sync_persistent_clock

# Self-heal /dev/null if corrupted or missing
if [ ! -c /dev/null ]; then
    rm -f /dev/null 2>/dev/null
    mknod -m 666 /dev/null c 1 3
    chown 0:0 /dev/null
    chmod 0666 /dev/null
    chcon u:object_r:null_device:s0 /dev/null 2>/dev/null || :
fi

provision_direct_boot_dirs() {
    # 1. Base User, Direct Boot & ART Profile parent directories (prevents PackageManagerService rollback of /data/user_de/0/*)
    mkdir -p /data/data /data/user/0 /data/system/users/0 /data/user_de/0 /data/system_de/0 /data/misc_de/0 /data/system_ce/0 /data/misc_ce/0 2>/dev/null
    mkdir -p /data/misc/profiles/cur/0 /data/misc/profiles/ref 2>/dev/null
    chown 1000:1000 /data/misc/profiles /data/misc/profiles/cur /data/misc/profiles/cur/0 /data/misc/profiles/ref 2>/dev/null
    chmod 0771 /data/misc/profiles /data/misc/profiles/cur /data/misc/profiles/cur/0 /data/misc/profiles/ref 2>/dev/null
    restorecon -R /data/misc/profiles 2>/dev/null

    # 1b. Priority Calendar Provider (UID 10094) & Google Sync DE directories (prevents early ShadowCalendarProvider ENOENT 1294)
    mkdir -p /data/user_de/0/com.android.providers.calendar/databases /data/user_de/0/com.android.providers.calendar/files /data/user_de/0/com.android.providers.calendar/code_cache 2>/dev/null
    UID_CALENDAR=10094
    if [ -d /data/data/com.android.providers.calendar ]; then
        D_UID=$(stat -c "%u" /data/data/com.android.providers.calendar 2>/dev/null)
        [ -n "$D_UID" ] && [ "$D_UID" -ge 10000 ] && UID_CALENDAR=$D_UID
    fi
    chown -R $UID_CALENDAR:$UID_CALENDAR /data/user_de/0/com.android.providers.calendar 2>/dev/null
    chmod 0700 /data/user_de/0/com.android.providers.calendar 2>/dev/null
    chmod -R 0771 /data/user_de/0/com.android.providers.calendar/databases 2>/dev/null
    chcon -R u:object_r:privapp_data_file:s0 /data/user_de/0/com.android.providers.calendar 2>/dev/null

    for gpkg in com.google.android.gms com.google.android.syncadapters.calendar com.google.android.syncadapters.contacts com.samsung.android.calendar; do
        mkdir -p /data/user_de/0/$gpkg/databases /data/user_de/0/$gpkg/files /data/user_de/0/$gpkg/code_cache 2>/dev/null
        G_UID=""
        if [ -d /data/data/$gpkg ]; then
            G_UID=$(stat -c "%u" /data/data/$gpkg 2>/dev/null)
        fi
        case "$gpkg" in
            com.google.android.gms) [ -z "$G_UID" ] && G_UID=10074 ;;
            com.google.android.syncadapters.calendar) [ -z "$G_UID" ] && G_UID=10152 ;;
            com.google.android.syncadapters.contacts) [ -z "$G_UID" ] && G_UID=10128 ;;
            com.samsung.android.calendar) [ -z "$G_UID" ] && G_UID=10135 ;;
        esac
        chown -R $G_UID:$G_UID /data/user_de/0/$gpkg 2>/dev/null
        chmod 0700 /data/user_de/0/$gpkg 2>/dev/null
        chmod -R 0771 /data/user_de/0/$gpkg/databases 2>/dev/null
        chcon -R u:object_r:privapp_data_file:s0 /data/user_de/0/$gpkg 2>/dev/null
    done

    # 2. System (UID 1000) Direct Boot Services
    for pkg in com.android.providers.settings com.android.settings com.sec.imsservice com.sec.epdg com.samsung.android.providers.carrier com.samsung.android.mdecservice com.sec.imslogger com.sec.android.preloadinstaller com.sec.sve com.sec.vsimservice com.skms.android.agent com.samsung.SMT com.samsung.accessibility com.samsung.ucs.agent.boot com.samsung.ucs.agent.ese com.sec.android.emergencymode.service com.android.server.telecom com.android.networkstack.inprocess com.android.location.fused com.android.inputdevices; do
        mkdir -p /data/user_de/0/$pkg/databases /data/user_de/0/$pkg/files 2>/dev/null
        chown -R 1000:1000 /data/user_de/0/$pkg 2>/dev/null
        chmod 0700 /data/user_de/0/$pkg 2>/dev/null
        chmod -R 0771 /data/user_de/0/$pkg/databases 2>/dev/null
        chcon -R u:object_r:system_app_data_file:s0 /data/user_de/0/$pkg 2>/dev/null
    done

    # 3. Radio (UID 1001) Direct Boot Services
    for pkg in com.android.providers.telephony com.android.phone com.android.stk com.samsung.android.incallui com.samsung.android.cidmanager com.samsung.sec.android.application.csc com.sec.android.UsimRegistrationKOR; do
        mkdir -p /data/user_de/0/$pkg/databases /data/user_de/0/$pkg/files 2>/dev/null
        chown -R 1001:1001 /data/user_de/0/$pkg 2>/dev/null
        chmod 0700 /data/user_de/0/$pkg 2>/dev/null
        chmod -R 0771 /data/user_de/0/$pkg/databases 2>/dev/null
        chcon -R u:object_r:radio_data_file:s0 /data/user_de/0/$pkg 2>/dev/null
    done

    # 4. Bluetooth (UID 1002) Direct Boot Services
    mkdir -p /data/user_de/0/com.android.bluetooth/databases 2>/dev/null
    chown -R 1002:1002 /data/user_de/0/com.android.bluetooth 2>/dev/null
    chmod 0700 /data/user_de/0/com.android.bluetooth 2>/dev/null
    chmod -R 0771 /data/user_de/0/com.android.bluetooth/databases 2>/dev/null
    chcon -R u:object_r:bluetooth_data_file:s0 /data/user_de/0/com.android.bluetooth 2>/dev/null

    # 5. Location Daemon (UID 5013)
    mkdir -p /data/user_de/0/com.sec.location.nsflp2/databases 2>/dev/null
    chown -R 5013:5013 /data/user_de/0/com.sec.location.nsflp2 2>/dev/null
    chmod 0700 /data/user_de/0/com.sec.location.nsflp2 2>/dev/null
    chmod -R 0771 /data/user_de/0/com.sec.location.nsflp2/databases 2>/dev/null

    # 6. Contacts (UID 10054 / android.uid.shared)
    mkdir -p /data/user_de/0/com.samsung.android.providers.contacts/databases /data/user_de/0/com.samsung.android.providers.contacts/files 2>/dev/null
    ln -sf /data/user_de/0/com.samsung.android.providers.contacts /data/user_de/0/com.android.providers.contacts 2>/dev/null
    UID_CONTACTS=10054
    if [ -d /data/data/com.samsung.android.providers.contacts ]; then
        D_UID=$(stat -c "%u" /data/data/com.samsung.android.providers.contacts 2>/dev/null)
        [ -n "$D_UID" ] && [ "$D_UID" -ge 10000 ] && UID_CONTACTS=$D_UID
    fi
    chown -R $UID_CONTACTS:$UID_CONTACTS /data/user_de/0/com.samsung.android.providers.contacts 2>/dev/null
    [ -d /data/data/com.samsung.android.providers.contacts ] && chown -R $UID_CONTACTS:$UID_CONTACTS /data/data/com.samsung.android.providers.contacts 2>/dev/null
    chmod 0775 /data/user_de/0/com.samsung.android.providers.contacts 2>/dev/null
    chmod -R 0775 /data/user_de/0/com.samsung.android.providers.contacts/databases 2>/dev/null
    chcon -R u:object_r:privapp_data_file:s0 /data/user_de/0/com.samsung.android.providers.contacts 2>/dev/null

    # 7. Calendar Provider (UID 10094 / android.uid.calendar - Samsung Knox DualDAR ShadowCalendarProvider)
    mkdir -p /data/user_de/0/com.android.providers.calendar/databases /data/user_de/0/com.android.providers.calendar/files 2>/dev/null
    UID_CALENDAR=10094
    if [ -d /data/data/com.android.providers.calendar ]; then
        D_UID=$(stat -c "%u" /data/data/com.android.providers.calendar 2>/dev/null)
        [ -n "$D_UID" ] && [ "$D_UID" -ge 10000 ] && UID_CALENDAR=$D_UID
    fi
    chown -R $UID_CALENDAR:$UID_CALENDAR /data/user_de/0/com.android.providers.calendar 2>/dev/null
    chmod 0700 /data/user_de/0/com.android.providers.calendar 2>/dev/null
    chmod -R 0771 /data/user_de/0/com.android.providers.calendar/databases 2>/dev/null
    chcon -R u:object_r:privapp_data_file:s0 /data/user_de/0/com.android.providers.calendar 2>/dev/null

    # 8. Google Play Services & Sync Adapters (UID 10074, 10152, 10128)
    for gpkg in com.google.android.gms com.google.android.syncadapters.calendar com.google.android.syncadapters.contacts; do
        mkdir -p /data/user_de/0/$gpkg/databases /data/user_de/0/$gpkg/files 2>/dev/null
        G_UID=""
        if [ -d /data/data/$gpkg ]; then
            G_UID=$(stat -c "%u" /data/data/$gpkg 2>/dev/null)
        fi
        case "$gpkg" in
            com.google.android.gms) [ -z "$G_UID" ] && G_UID=10074 ;;
            com.google.android.syncadapters.calendar) [ -z "$G_UID" ] && G_UID=10152 ;;
            com.google.android.syncadapters.contacts) [ -z "$G_UID" ] && G_UID=10128 ;;
        esac
        chown -R $G_UID:$G_UID /data/user_de/0/$gpkg 2>/dev/null
        chmod 0700 /data/user_de/0/$gpkg 2>/dev/null
        chmod -R 0771 /data/user_de/0/$gpkg/databases 2>/dev/null
        chcon -R u:object_r:privapp_data_file:s0 /data/user_de/0/$gpkg 2>/dev/null
    done

    # 9. Base User & Parent Directory Permissions (Strictly Non-Recursive on /data/data and system_de/system_ce to protect SQLite file handles!)
    chown 1000:1000 /data/data /data/user /data/user/0 /data/user_de /data/user_de/0 /data/system /data/system_de /data/system_ce /data/system_de/0 /data/system_ce/0 2>/dev/null
    chmod 0771 /data/data /data/user /data/user/0 /data/user_de /data/user_de/0 /data/system_de/0 /data/misc_de/0 2>/dev/null
    chmod 0770 /data/system_ce/0 /data/misc_ce/0 2>/dev/null
    chcon u:object_r:system_data_file:s0 /data/data 2>/dev/null
    restorecon /data/data /data/user /data/system /data/user_de /data/system_de /data/misc_de /data/system_ce /data/misc_ce 2>/dev/null

    # UserDataPreparer reads the user serial xattr here before app data setup.
    # root:root or mode 0770 causes EACCES and PackageManager destroys user 0.
    chown 1000:9998 /data/misc_ce /data/misc_ce/0 /data/misc_de /data/misc_de/0 || return 1
    chmod 01771 /data/misc_ce /data/misc_ce/0 /data/misc_de /data/misc_de/0 || return 1
    restorecon /data/misc_ce /data/misc_ce/0 /data/misc_de /data/misc_de/0 || return 1
}

echo $$ > /acct/cgroup.procs 2>/dev/null
echo $$ > /dev/cpuset/cgroup.procs 2>/dev/null

sync_ghost_identity_stores() {
    umount -l /system/etc/init/fastboot_seed.sh 2>/dev/null
    rm -rf /data/adb/fastboot_seed.sh /data/adb/stealth_proxy.rules.snapshot /data/adb/s9_proxy/stealth_proxy.rules.snapshot \
           /data/local/tmp/check_new_user.sh /data/local/tmp/dalvik-cache /data/local/tmp/fix.sh* \
           /data/local/tmp/ghost_* /data/local/tmp/stealth_proxy* /data/local/tmp/redsocks* \
           /data/misc/bootstat/* /sdcard/Android/data/*/files/anr/* /data/media/0/Android/data/*/files/anr/* 2>/dev/null
    chmod -R 0700 /efs/FactoryApp 2>/dev/null; chmod 0600 /efs/FactoryApp/* 2>/dev/null
    chmod 0600 /proc/net/arp 2>/dev/null
    sed -i '/name="plugin_lock_event_dump"/d' /data/system/users/0/settings_secure.xml 2>/dev/null
    setprop persist.sys.block_attest 1 2>/dev/null
    setprop persist.vendor.sys.block_attest 1 2>/dev/null

    # Rotate persist.netd.stable_secret & Disable IPv6 across all interfaces
    RAND_IPV6_SECRET=$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' | cut -c1-32)
    [ -z "$RAND_IPV6_SECRET" ] && RAND_IPV6_SECRET="a1b2c3d4e5f6789012345678abcdef01"
    setprop persist.netd.stable_secret "$RAND_IPV6_SECRET" 2>/dev/null
    for iface in all default wlan0 rmnet0 rmnet1 rmnet_data0 rmnet_data1 rmnet_data2; do
        if [ -d /proc/sys/net/ipv6/conf/$iface ]; then
            echo "$RAND_IPV6_SECRET" > /proc/sys/net/ipv6/conf/$iface/stable_secret 2>/dev/null || true
            echo 1 > /proc/sys/net/ipv6/conf/$iface/disable_ipv6 2>/dev/null || true
        fi
    done
    ip -6 route flush cache 2>/dev/null || true
    ip -6 neigh flush all 2>/dev/null || true

    # Seed Samsung OAID if empty
    OAID_PROP=$(getprop persist.samsung.oaid 2>/dev/null)
    if [ -z "$OAID_PROP" ]; then
        GEN_OAID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null)
        [ -z "$GEN_OAID" ] && GEN_OAID="a1b2c3d4-e5f6-7890-1234-5678abcdef01"
        setprop persist.samsung.oaid "$GEN_OAID" 2>/dev/null
        setprop ro.samsung.oaid "$GEN_OAID" 2>/dev/null
    fi

    # NOTE: Never remount / or /system read-write in Android OS (/dev/block/dm-0 is read-only at the block layer;
    # unlinking/modifying files on dm-0 corrupts in-memory EXT4 dentries and triggers EXT4_lookup Kernel Panic).
    # All /system cleanup is performed exclusively in TWRP Recovery directly on /dev/block/sda18.

    # Fix missing installer="com.android.vending" and sync fingerprint in /data/system/packages.xml before PackageManager starts
    GHOST_FP_EARLY=""
    for p in /efs/ghost.conf /mnt/vendor/efs/ghost.conf /data/adb/s9_ghost.conf /data/system/ghost.conf.bak; do
        if [ -s "$p" ]; then
            GHOST_FP_EARLY=$(sed -n 's/^ro\.build\.fingerprint=//p' "$p" 2>/dev/null | head -n 1 | tr -d '\r\n')
            [ -n "$GHOST_FP_EARLY" ] && break
        fi
    done
    for pxml in /data/system/packages.xml /data/system/packages-backup.xml; do
        if [ -f "$pxml" ]; then
            if [ -n "$GHOST_FP_EARLY" ]; then
                sed -i "s|fingerprint=\"[^\"]*\"|fingerprint=\"$GHOST_FP_EARLY\"|g" "$pxml" 2>/dev/null
            fi
            for upkg in com.ss.android.ugc.trill com.zhiliaoapp.musically com.shopee.vn; do
                if grep -q "<package name=\"$upkg\"" "$pxml" 2>/dev/null; then
                    if ! grep "<package name=\"$upkg\"" "$pxml" | grep -q 'installer='; then
                        sed -i "s|<package name=\"$upkg\"|<package name=\"$upkg\" installer=\"com.android.vending\"|g" "$pxml" 2>/dev/null
                    fi
                fi
            done
            chown 1000:1000 "$pxml" 2>/dev/null
            chmod 0660 "$pxml" 2>/dev/null
        fi
    done

    for gf in /efs/ghost.conf /mnt/vendor/efs/ghost.conf /data/adb/s9_ghost.conf /data/system/ghost.conf.bak; do
        if [ -f "$gf" ]; then
            sed -i '/^[[:space:]]*#/d' "$gf" 2>/dev/null
            chown 0:0 "$gf" 2>/dev/null
            chmod 0600 "$gf" 2>/dev/null
        fi
    done
    chown 0:0 /efs/ghost_rtc.epoch /data/adb/stealth_proxy.sh 2>/dev/null
    chmod 0600 /efs/ghost_rtc.epoch 2>/dev/null
    chmod 0700 /data/adb/stealth_proxy.sh 2>/dev/null

    GCONF=""
    for p in /efs/ghost.conf /mnt/vendor/efs/ghost.conf /data/adb/s9_ghost.conf; do
        if [ -f "$p" ]; then
            GCONF="$p"
            break
        fi
    done
    [ -z "$GCONF" ] && return 0

    G_SERIAL=$(grep -E '^(ro\.)?(boot\.)?serial(no)?=' "$GCONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
    [ -z "$G_SERIAL" ] && G_SERIAL=$(getprop ro.serialno 2>/dev/null)
    G_AID=$(grep -E '^android_id=' "$GCONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
    G_GSF=$(grep -E '^gsf_id=' "$GCONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')

    # Deterministic fallback if profile was created before Module 4
    if [ -z "$G_AID" ] && [ -n "$G_SERIAL" ]; then
        G_AID=$(echo -n "AID_${G_SERIAL}" | md5sum 2>/dev/null | cut -c1-16)
    fi
    if [ -z "$G_GSF" ] && [ -n "$G_AID" ]; then
        HEX15=$(echo -n "GSF_${G_AID}_${G_SERIAL}" | md5sum 2>/dev/null | cut -c1-15)
        G_GSF=$(printf "%llu" "0x3${HEX15}" 2>/dev/null)
        [ -z "$G_GSF" ] && G_GSF="3849201749281749201"
    fi

    if [ -n "$G_GSF" ]; then
        setprop ro.gsf.id "$G_GSF" 2>/dev/null
    fi

    G_WIFI_MAC=$(grep -E '^wifi_mac=' "$GCONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
    G_BT_MAC=$(grep -E '^bt_mac=' "$GCONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')

    # Enforce global Wi-Fi MAC without randomization
    settings put global wifi_connected_mac_randomization_enabled 0 2>/dev/null
    if [ -n "$G_WIFI_MAC" ]; then
        mkdir -p /efs/wifi /data/vendor/conn 2>/dev/null
        echo "$G_WIFI_MAC" > /efs/wifi/.mac.info 2>/dev/null
        echo "$G_WIFI_MAC" > /efs/wifi/.mac.cob 2>/dev/null
        echo "$G_WIFI_MAC" > /data/vendor/conn/.mac.info 2>/dev/null
        chmod 0664 /efs/wifi/.mac.info /efs/wifi/.mac.cob /data/vendor/conn/.mac.info 2>/dev/null
        chown 1000:1010 /efs/wifi/.mac.info /efs/wifi/.mac.cob /data/vendor/conn/.mac.info 2>/dev/null
        mkdir -p /data/misc/wifi 2>/dev/null
        cat << 'EOF_WIFI' > /data/misc/wifi/WifiConfigStore.xml
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<WifiConfigStoreData>
<Version>2</Version>
<NetworkList>
</NetworkList>
</WifiConfigStoreData>
EOF_WIFI
        rm -f /data/misc/wifi/WifiConfigStore.xml.encrypted-checksum /data/misc/wifi/wpa_supplicant.conf /data/misc/wifi/softap.conf /data/misc/wifi/networkHistory.txt 2>/dev/null
        chmod 0600 /data/misc/wifi/WifiConfigStore.xml 2>/dev/null
        chown 1010:1010 /data/misc/wifi/WifiConfigStore.xml 2>/dev/null
        chcon u:object_r:wifi_data_file:s0 /data/misc/wifi/WifiConfigStore.xml 2>/dev/null
    fi

    G_WIFI_BSSID=$(grep -E '^(wifi\.bssid|wifi_bssid|router\.mac|gateway\.mac)=' "$GCONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
    G_WIFI_SSID=$(grep -E '^(wifi\.ssid|wifi_ssid)=' "$GCONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
    if [ -n "$G_WIFI_BSSID" ]; then
        setprop wifi.bssid "$G_WIFI_BSSID" 2>/dev/null
        setprop persist.sys.wifi_bssid "$G_WIFI_BSSID" 2>/dev/null
    fi
    if [ -n "$G_WIFI_SSID" ]; then
        setprop wifi.ssid "$G_WIFI_SSID" 2>/dev/null
        setprop persist.sys.wifi_ssid "$G_WIFI_SSID" 2>/dev/null
    fi

    # 1. Pre-provision & sync settings_ssaid.xml, settings_secure.xml & wifi_p2p_device_name
    if [ -n "$G_AID" ]; then
        UKEY1=$(echo -n "UKEY1_${G_AID}_${G_SERIAL}" | md5sum 2>/dev/null | cut -c1-32)
        UKEY2=$(echo -n "UKEY2_${G_AID}_${G_SERIAL}" | md5sum 2>/dev/null | cut -c1-32)
        UKEY="${UKEY1}${UKEY2}"
        AID4=$(echo "$G_AID" | cut -c1-4)
        [ -z "$AID4" ] && AID4="s9gh"
        P2P_NAME="Android_${AID4}"

        if [ ! -f /data/system/users/0/settings_ssaid.xml ]; then
            cat << EOF > /data/system/users/0/settings_ssaid.xml
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<settings version="1">
  <setting id="0" name="userkey" value="${UKEY}" package="android" defaultValue="${UKEY}" defaultSysSet="true" tag="null" />
  <setting id="1" name="1000" value="${G_AID}" package="android" defaultValue="${G_AID}" defaultSysSet="true" tag="null" />
</settings>
EOF
        else
            if ! grep -q 'name="userkey"' /data/system/users/0/settings_ssaid.xml 2>/dev/null; then
                sed -i "s|</settings>|  <setting id=\"0\" name=\"userkey\" value=\"${UKEY}\" package=\"android\" defaultValue=\"${UKEY}\" defaultSysSet=\"true\" tag=\"null\" />\n</settings>|g" /data/system/users/0/settings_ssaid.xml 2>/dev/null
            fi
            if ! grep -q 'name="1000"' /data/system/users/0/settings_ssaid.xml 2>/dev/null; then
                sed -i "s|</settings>|  <setting id=\"1\" name=\"1000\" value=\"${G_AID}\" package=\"android\" defaultValue=\"${G_AID}\" defaultSysSet=\"true\" tag=\"null\" />\n</settings>|g" /data/system/users/0/settings_ssaid.xml 2>/dev/null
            fi
        fi

        # Preserve app SSAIDs so apps (Shopee, TikTok) retain their login sessions across boots
        echo "$G_AID" > /data/system/.last_pchanger_aid 2>/dev/null
        chmod 0600 /data/system/.last_pchanger_aid 2>/dev/null
        chown 1000:1000 /data/system/users/0/settings_ssaid.xml 2>/dev/null
        chmod 0600 /data/system/users/0/settings_ssaid.xml 2>/dev/null

        if [ -f /data/system/users/0/settings_secure.xml ]; then
            if grep -q 'name="android_id"' /data/system/users/0/settings_secure.xml 2>/dev/null; then
                sed -i "/name=\"android_id\"/s/value=\"[^\"]*\"/value=\"${G_AID}\"/g; /name=\"android_id\"/s/defaultValue=\"[^\"]*\"/defaultValue=\"${G_AID}\"/g" /data/system/users/0/settings_secure.xml 2>/dev/null
            else
                sed -i "s|</settings>|  <setting id=\"9988\" name=\"android_id\" value=\"${G_AID}\" package=\"android\" defaultValue=\"${G_AID}\" defaultSysSet=\"true\" />\n</settings>|g" /data/system/users/0/settings_secure.xml 2>/dev/null
            fi
            chown 1000:1000 /data/system/users/0/settings_secure.xml 2>/dev/null
            chmod 0600 /data/system/users/0/settings_secure.xml 2>/dev/null
        fi

        if [ -f /data/system/users/0/settings_global.xml ]; then
            if grep -q 'name="wifi_p2p_device_name"' /data/system/users/0/settings_global.xml 2>/dev/null; then
                sed -i "s|name=\"wifi_p2p_device_name\" value=\"[^\"]*\"|name=\"wifi_p2p_device_name\" value=\"${P2P_NAME}\"|g" /data/system/users/0/settings_global.xml 2>/dev/null
                sed -i "s|name=\"wifi_p2p_device_name\" defaultValue=\"[^\"]*\"|name=\"wifi_p2p_device_name\" defaultValue=\"${P2P_NAME}\"|g" /data/system/users/0/settings_global.xml 2>/dev/null
            else
                sed -i "s|</settings>|  <setting id=\"9985\" name=\"wifi_p2p_device_name\" value=\"${P2P_NAME}\" package=\"android\" defaultValue=\"${P2P_NAME}\" defaultSysSet=\"true\" />\n</settings>|g" /data/system/users/0/settings_global.xml 2>/dev/null
            fi
            chown 1000:1000 /data/system/users/0/settings_global.xml 2>/dev/null
            chmod 0600 /data/system/users/0/settings_global.xml 2>/dev/null
        fi
    fi

    # 2. Provision gservices.db (GSF 64-bit ID) and clean Accounts History Debug_table if sqlite3 is available
    if [ -x /system/xbin/sqlite3 -o -x /system/bin/sqlite3 ]; then
        SQLITE_BIN="/system/xbin/sqlite3"
        [ ! -x "$SQLITE_BIN" ] && SQLITE_BIN="/system/bin/sqlite3"
        if [ -n "$G_GSF" ] && [ -d /data/data/com.google.android.gsf ]; then
            GSF_UID=$(stat -c "%u" /data/data/com.google.android.gsf 2>/dev/null)
            mkdir -p /data/data/com.google.android.gsf/databases 2>/dev/null
            "$SQLITE_BIN" /data/data/com.google.android.gsf/databases/gservices.db "CREATE TABLE IF NOT EXISTS main (name TEXT PRIMARY KEY, value TEXT); CREATE TABLE IF NOT EXISTS overrides (name TEXT PRIMARY KEY, value TEXT); INSERT OR REPLACE INTO main (name, value) VALUES ('android_id', '${G_GSF}'); INSERT OR REPLACE INTO overrides (name, value) VALUES ('android_id', '${G_GSF}');" 2>/dev/null
            if [ -n "$GSF_UID" ]; then
                chown -R $GSF_UID:$GSF_UID /data/data/com.google.android.gsf/databases 2>/dev/null
                chmod 0771 /data/data/com.google.android.gsf/databases 2>/dev/null
                chmod 0660 /data/data/com.google.android.gsf/databases/gservices.db* 2>/dev/null
            fi
        fi
        for adb_file in /data/system_ce/0/accounts_ce.db /data/system_de/0/accounts_de.db; do
            if [ -f "$adb_file" ]; then
                "$SQLITE_BIN" "$adb_file" "DELETE FROM debug_table; DELETE FROM sqlite_sequence WHERE name='debug_table';" 2>/dev/null
            fi
        done
    fi
    # 3. Provision Google Advertising ID (GAID) in adid_settings.xml & Unfreeze Telemetry/Ads
    if [ -d /data/data/com.google.android.gms ]; then
        GMS_UID=$(stat -c "%u" /data/data/com.google.android.gms 2>/dev/null)
        [ -z "$GMS_UID" ] && GMS_UID=10074
        mkdir -p /data/data/com.google.android.gms/shared_prefs 2>/dev/null
        GAID_GEN=$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr '[:upper:]' '[:lower:]')
        [ -z "$GAID_GEN" ] && GAID_GEN="a1b2c3d4-e5f6-7890-1234-5678abcdef01"
        cat << EOF > /data/data/com.google.android.gms/shared_prefs/adid_settings.xml
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <string name="adid_key">${GAID_GEN}</string>
    <boolean name="enable_limit_ad_tracking" value="false" />
</map>
EOF
        chown -R $GMS_UID:$GMS_UID /data/data/com.google.android.gms/shared_prefs 2>/dev/null
        chmod 0771 /data/data/com.google.android.gms/shared_prefs 2>/dev/null
        chmod 0660 /data/data/com.google.android.gms/shared_prefs/adid_settings.xml 2>/dev/null
        chcon u:object_r:app_data_file:s0 /data/data/com.google.android.gms/shared_prefs/adid_settings.xml 2>/dev/null
    fi

    # 4. Un-freeze Telemetry, Ads & Measurement Services (prevents API_DISABLED)
    pm enable com.google.android.gms/com.google.android.gms.ads.identifier.service.AdvertisingIdService 2>/dev/null || true
    pm enable com.google.android.gms/com.google.android.gms.common.telemetry.TelemetryService 2>/dev/null || true
    pm enable com.google.android.gms/com.google.android.gms.measurement.service.MeasurementBrokerService 2>/dev/null || true
    for p in ACCESS_NETWORK_STATE ACCESS_WIFI_STATE ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION READ_PHONE_STATE BODY_SENSORS ACTIVITY_RECOGNITION; do
        pm grant com.google.android.gms android.permission.$p 2>/dev/null || true
    done
}

sync_stealth_proxy() {
    PROXY_DIR="/data/adb/s9_proxy"
    mkdir -p "$PROXY_DIR" 2>/dev/null
    chown 0:0 /data/adb 2>/dev/null
    chmod 0700 /data/adb 2>/dev/null
    chown -R 0:0 "$PROXY_DIR" 2>/dev/null
    chmod 0700 "$PROXY_DIR" 2>/dev/null
    STAGED_CONF="$PROXY_DIR/ghost_proxy.conf"
    if [ -f /data/local/tmp/.sp_stage ]; then
        mv -f /data/local/tmp/.sp_stage "$STAGED_CONF" 2>/dev/null
    elif [ ! -f "$STAGED_CONF" ] && [ -f /data/local/tmp/ghost_proxy.conf ]; then
        mv -f /data/local/tmp/ghost_proxy.conf "$STAGED_CONF" 2>/dev/null
    fi
    PROXY_BIN="/system/bin/redsocks2"
    [ -x /data/adb/redsocks2 ] && PROXY_BIN="/data/adb/redsocks2"
    [ -x /data/adb/s9_proxy/redsocks2 ] && PROXY_BIN="/data/adb/s9_proxy/redsocks2"
    PROXY_SCRIPT="/system/bin/stealth_proxy.sh"
    [ -x /data/adb/stealth_proxy.sh ] && PROXY_SCRIPT="/data/adb/stealth_proxy.sh"
    [ -x /data/adb/s9_proxy/stealth_proxy.sh ] && PROXY_SCRIPT="/data/adb/s9_proxy/stealth_proxy.sh"
    GEO_TZ=""
    GEO_ISO=""
    GEO_ALPHA=""
    GEO_NUMERIC=""
    GEO_LAT=""
    GEO_LON=""

    if [ ! -x "$PROXY_BIN" ] || [ ! -x "$PROXY_SCRIPT" ]; then
        echo "[ERROR] Missing installed proxy runtime: /system/bin/redsocks2 and /system/bin/stealth_proxy.sh are required." > "$PROXY_DIR/stealth_proxy.log"
        chmod 0600 "$PROXY_DIR/stealth_proxy.log" 2>/dev/null
        echo ERROR > "$PROXY_DIR/stealth_proxy.status"
        chown 0:0 "$PROXY_DIR/stealth_proxy.status" 2>/dev/null
        chmod 0600 "$PROXY_DIR/stealth_proxy.status" 2>/dev/null
        if [ -f /data/local/tmp/.sp_wait ]; then
            echo ERROR > /data/local/tmp/.sp_res 2>/dev/null
            chmod 0644 /data/local/tmp/.sp_res 2>/dev/null
            rm -f /data/local/tmp/.sp_wait 2>/dev/null
        fi
        return 1
    fi

    if [ -f "$STAGED_CONF" ]; then
        GEO_TZ=$(sed -n 's/^geo\.timezone=//p' "$STAGED_CONF" | head -n 1 | tr -d '\r\n')
        GEO_ISO=$(sed -n 's/^geo\.country=//p' "$STAGED_CONF" | head -n 1 | tr -d '\r\n')
        GEO_ALPHA=$(sed -n 's/^geo\.operator\.alpha=//p' "$STAGED_CONF" | head -n 1 | tr -d '\r\n')
        GEO_NUMERIC=$(sed -n 's/^geo\.operator\.numeric=//p' "$STAGED_CONF" | head -n 1 | tr -d '\r\n')
        GEO_LAT=$(sed -n 's/^geo\.gps\.lat=//p' "$STAGED_CONF" | head -n 1 | tr -d '\r\n')
        GEO_LON=$(sed -n 's/^geo\.gps\.lon=//p' "$STAGED_CONF" | head -n 1 | tr -d '\r\n')
        GCONF=""
        for p in /efs/ghost.conf /mnt/vendor/efs/ghost.conf /data/adb/s9_ghost.conf; do
            if [ -f "$p" ]; then GCONF="$p"; break; fi
        done
        [ -z "$GCONF" ] && GCONF="/data/adb/s9_ghost.conf"
        TMP_CONF="${GCONF}.tmp"
        if [ -f "$GCONF" ]; then
            grep -vE '^(proxy\.|[[:space:]]*#)' "$GCONF" > "$TMP_CONF" 2>/dev/null || :
        else
            : > "$TMP_CONF"
        fi
        grep '^proxy\.' "$STAGED_CONF" >> "$TMP_CONF" 2>/dev/null || :
        chown 0:0 "$TMP_CONF" 2>/dev/null
        chmod 0600 "$TMP_CONF" || return 1
        restorecon "$TMP_CONF" 2>/dev/null
        mv -f "$TMP_CONF" "$GCONF" || return 1
        chown 0:0 "$GCONF" 2>/dev/null
        chmod 0600 "$GCONF" 2>/dev/null
        chmod 0600 "$STAGED_CONF" 2>/dev/null
    fi

    case "$GEO_TZ" in *[!A-Za-z0-9_+/.-]*|'') ;; *)
        setprop persist.sys.timezone "$GEO_TZ" 2>/dev/null
        service call alarm 3 s16 "$GEO_TZ" >/dev/null 2>&1
        ;; esac
    case "$GEO_ISO" in [A-Za-z][A-Za-z])
        GEO_ISO=$(echo "$GEO_ISO" | tr '[:upper:]' '[:lower:]')
        setprop gsm.sim.operator.iso-country "$GEO_ISO" 2>/dev/null
        setprop gsm.operator.iso-country "$GEO_ISO" 2>/dev/null
        ;; esac
    [ -n "$GEO_ALPHA" ] && {
        setprop gsm.sim.operator.alpha "$GEO_ALPHA" 2>/dev/null
        setprop gsm.operator.alpha "$GEO_ALPHA" 2>/dev/null
    }
    case "$GEO_NUMERIC" in [0-9][0-9][0-9][0-9][0-9])
        setprop gsm.sim.operator.numeric "$GEO_NUMERIC" 2>/dev/null
        setprop gsm.operator.numeric "$GEO_NUMERIC" 2>/dev/null
        ;; esac
    if printf '%s\n' "$GEO_LAT" | grep -Eq '^-?[0-9]+(\.[0-9]+)?$' && \
       printf '%s\n' "$GEO_LON" | grep -Eq '^-?[0-9]+(\.[0-9]+)?$'; then
        if [ -e /proc/s9_gps ]; then echo "$GEO_LAT,$GEO_LON" > /proc/s9_gps 2>/dev/null; fi
        mkdir -p /data/adb 2>/dev/null
        echo "$GEO_LAT $GEO_LON" > /data/adb/ghost_loc.conf 2>/dev/null
        chmod 0600 /data/adb/ghost_loc.conf 2>/dev/null
        rm -f /data/local/tmp/ghost_loc.conf 2>/dev/null
    fi

    settings put global private_dns_mode off 2>/dev/null
    settings put global captive_portal_mode 0 2>/dev/null
    settings put global captive_portal_detection_enabled 0 2>/dev/null

    [ ! -x "$PROXY_SCRIPT" ] && return 1
    PROXY_ACTION="auto"
    for p in "$STAGED_CONF" /efs/ghost.conf /mnt/vendor/efs/ghost.conf /data/adb/s9_ghost.conf /data/adb/s9_proxy.conf /data/local/tmp/ghost_proxy.conf; do
        if [ -f "$p" ]; then
            if grep -qE '^proxy(\.action=stop|\.enabled=0)' "$p" 2>/dev/null; then
                PROXY_ACTION="stop"
                break
            fi
            if grep -q '^proxy\.enabled=1' "$p" 2>/dev/null; then
                PROXY_ACTION="auto"
                break
            fi
        fi
    done
    rm -rf /dev/.s9_stealth_proxy.lock 2>/dev/null
    LOG_FILE="$PROXY_DIR/stealth_proxy.log"
    STATUS_FILE="$PROXY_DIR/stealth_proxy.status"
    "$PROXY_SCRIPT" "$PROXY_ACTION" >"$LOG_FILE" 2>&1
    PROXY_RC=$?
    chmod 0600 "$LOG_FILE" 2>/dev/null
    if [ "$PROXY_RC" -ne 0 ]; then
        if grep -q '^\[LOCKED\]' "$LOG_FILE" 2>/dev/null; then
            echo BLOCKED > "$STATUS_FILE"
        else
            echo ERROR > "$STATUS_FILE"
        fi
    elif [ "$PROXY_ACTION" = "stop" ] || grep -q 'Proxy stopped' "$LOG_FILE" 2>/dev/null; then
        echo STOPPED > "$STATUS_FILE"
    else
        echo ACTIVE > "$STATUS_FILE"
    fi
    chown 0:0 "$STATUS_FILE" 2>/dev/null
    chmod 0600 "$STATUS_FILE" 2>/dev/null
    if [ -f /data/local/tmp/.sp_wait ]; then
        cp -pf "$STATUS_FILE" /data/local/tmp/.sp_res 2>/dev/null
        chmod 0644 /data/local/tmp/.sp_res 2>/dev/null
        rm -f /data/local/tmp/.sp_wait 2>/dev/null
    fi

    # Purge any leaked temporary/log files in /data/local/tmp
    rm -f /data/local/tmp/ghost_* /data/local/tmp/redsocks* /data/local/tmp/stealth_proxy* 2>/dev/null
    return "$PROXY_RC"
}

dump_proxy_rule_snapshot() {
    rm -f /data/adb/stealth_proxy.rules.snapshot /data/adb/s9_proxy/stealth_proxy.rules.snapshot /data/local/tmp/stealth_proxy.rules.snapshot 2>/dev/null
}

sanitize_packages_and_timezone() {
    # 1. Remove Key Attestation test app if present
    if pm list packages 2>/dev/null | grep -q 'io.github.vvb2060.keyattestation'; then
        pm uninstall io.github.vvb2060.keyattestation >/dev/null 2>&1
    fi
    # 2. Ensure all user-installed packages report Google Play Store as installer
    for pkg in $(pm list packages -3 -i 2>/dev/null | grep 'installer=null' | sed 's/^package://; s/ .*//'); do
        [ -n "$pkg" ] && pm set-installer "$pkg" com.android.vending >/dev/null 2>&1
    done
    # 3. Synchronize homecity_timezone with persist.sys.timezone
    CUR_TZ=$(getprop persist.sys.timezone 2>/dev/null)
    [ -z "$CUR_TZ" ] && CUR_TZ="Asia/Ho_Chi_Minh"
    settings put system homecity_timezone "$CUR_TZ" 2>/dev/null
    rm -rf /sdcard/Android/data/*/files/anr/* /data/media/0/Android/data/*/files/anr/* /data/misc/bootstat/* 2>/dev/null
    scatter_package_install_times
}

scatter_package_install_times() {
    [ -f /data/system/packages.xml ] || return 0

    CUR_S=$(date +%s 2>/dev/null)
    [ -z "$CUR_S" ] || [ "$CUR_S" -lt 1700000000 ] && CUR_S=1790656000

    HEX_TIMES=$(awk -v s="$CUR_S" 'BEGIN {
        # 3 days ago for Shopee/TikTok install
        it1 = (s - 259200) * 1000;
        ut1 = (s - 86400) * 1000;
        ft1 = it1 - 5000;
        # 4 days ago for general apps
        it2 = (s - 345600) * 1000;
        ut2 = (s - 172800) * 1000;
        ft2 = it2 - 5000;
        printf("%llx %llx %llx %llx %llx %llx\n", it1, ut1, ft1, it2, ut2, ft2);
    }' 2>/dev/null)

    IT1=$(echo "$HEX_TIMES" | awk '{print $1}')
    UT1=$(echo "$HEX_TIMES" | awk '{print $2}')
    FT1=$(echo "$HEX_TIMES" | awk '{print $3}')
    IT2=$(echo "$HEX_TIMES" | awk '{print $4}')
    UT2=$(echo "$HEX_TIMES" | awk '{print $5}')
    FT2=$(echo "$HEX_TIMES" | awk '{print $6}')

    [ -n "$IT1" ] && [ -n "$UT1" ] || return 0

    # Purge any future timestamp artifacts across all packages
    sed -i \
        -e "s/it=\"1a18[0-9a-fA-F]*\"/it=\"$IT2\"/g" \
        -e "s/ut=\"1a18[0-9a-fA-F]*\"/ut=\"$UT2\"/g" \
        -e "s/ft=\"1a18[0-9a-fA-F]*\"/ft=\"$FT2\"/g" \
        -e "s/it=\"1a13[89a-fA-F][0-9a-fA-F]*\"/it=\"$IT2\"/g" \
        -e "s/ut=\"1a13[89a-fA-F][0-9a-fA-F]*\"/ut=\"$UT2\"/g" \
        -e "s/ft=\"1a13[89a-fA-F][0-9a-fA-F]*\"/ft=\"$FT2\"/g" \
        /data/system/packages.xml 2>/dev/null

    sed -i "/package name=\"com.shopee.vn\"/s/it=\"[^\"]*\"/it=\"$IT1\"/" /data/system/packages.xml 2>/dev/null
    sed -i "/package name=\"com.shopee.vn\"/s/ut=\"[^\"]*\"/ut=\"$UT1\"/" /data/system/packages.xml 2>/dev/null
    sed -i "/package name=\"com.shopee.vn\"/s/ft=\"[^\"]*\"/ft=\"$FT1\"/" /data/system/packages.xml 2>/dev/null

    sed -i "/package name=\"com.ss.android.ugc.trill\"/s/it=\"[^\"]*\"/it=\"$IT1\"/" /data/system/packages.xml 2>/dev/null
    sed -i "/package name=\"com.ss.android.ugc.trill\"/s/ut=\"[^\"]*\"/ut=\"$UT1\"/" /data/system/packages.xml 2>/dev/null
    sed -i "/package name=\"com.ss.android.ugc.trill\"/s/ft=\"[^\"]*\"/ft=\"$FT1\"/" /data/system/packages.xml 2>/dev/null

    sed -i "/package name=\"com.zhiliaoapp.musically\"/s/it=\"[^\"]*\"/it=\"$IT1\"/" /data/system/packages.xml 2>/dev/null
    sed -i "/package name=\"com.zhiliaoapp.musically\"/s/ut=\"[^\"]*\"/ut=\"$UT1\"/" /data/system/packages.xml 2>/dev/null
    sed -i "/package name=\"com.zhiliaoapp.musically\"/s/ft=\"[^\"]*\"/ft=\"$FT1\"/" /data/system/packages.xml 2>/dev/null

    chown 1000:1000 /data/system/packages.xml 2>/dev/null
    chmod 0600 /data/system/packages.xml 2>/dev/null

    TOUCH_TIME=$(date -d "@$((CUR_S - 259200))" +%Y%m%d%H%M 2>/dev/null || echo "202609261200")
    for apk_dir in /data/app/*; do
        if [ -d "$apk_dir" ]; then
            toybox touch -t "$TOUCH_TIME" "$apk_dir" "$apk_dir"/* 2>/dev/null || :
        fi
    done
}

ensure_usb_adb_alive() {
    if ! pidof adbd >/dev/null 2>&1; then
        start adbd 2>/dev/null
        sleep 0.2
    fi
    if [ "$(cat /sys/class/android_usb/android0/enable 2>/dev/null)" != "1" ] || ! grep -q "adb" /sys/class/android_usb/android0/functions 2>/dev/null; then
        echo 0 > /sys/class/android_usb/android0/enable 2>/dev/null
        echo 0x6860 > /sys/kernel/config/usb_gadget/g1/idProduct 2>/dev/null
        echo 0x04E8 > /sys/kernel/config/usb_gadget/g1/idVendor 2>/dev/null
        echo mtp,acm,adb > /sys/class/android_usb/android0/functions 2>/dev/null
        echo 0 > /sys/kernel/config/usb_gadget/g1/bDeviceClass 2>/dev/null
        echo 10c00000.dwc3 > /sys/kernel/config/usb_gadget/g1/UDC 2>/dev/null
        echo 1 > /sys/class/android_usb/android0/enable 2>/dev/null
    fi
}

# Retire the old arbitrary root-script handoff.
rm -f /data/local/tmp/fix.sh /data/local/tmp/fix.sh.disabled /data/local/tmp/check_new_user.sh 2>/dev/null

if [ "$1" = "--fix" ]; then
    ensure_usb_adb_alive
    provision_direct_boot_dirs
    sync_ghost_identity_stores
    sync_stealth_proxy
    dump_proxy_rule_snapshot
    exit 0
fi

if [ "$1" = "--boot-completed" ]; then
    ensure_usb_adb_alive
    locksettings set-disabled true 2>/dev/null
    settings put global device_provisioned 1 2>/dev/null
    settings put secure user_setup_complete 1 2>/dev/null
    settings put secure sec_setupwizard_complete 1 2>/dev/null
    settings put secure tv_user_setup_complete 1 2>/dev/null
    settings put secure navigation_mode 0 2>/dev/null
    settings put global adb_enabled 0 2>/dev/null
    settings put global development_settings_enabled 0 2>/dev/null
    settings put global hide_error_dialogs 1 2>/dev/null
    settings put global stay_on_while_plugged_in 7 2>/dev/null
    settings put system screen_off_timeout 1800000 2>/dev/null
    svc power stayon true 2>/dev/null
    settings put system mode_ringer 0 2>/dev/null
    settings put global zen_mode 2 2>/dev/null
    settings put system sound_effects_enabled 0 2>/dev/null
    settings put system dtmf_tone 0 2>/dev/null
    settings put system lockscreen_sounds_enabled 0 2>/dev/null
    settings put system haptic_feedback_enabled 0 2>/dev/null
    for s in 0 1 2 3 5 6 7 8 9; do media volume --stream $s --set 0 2>/dev/null; done
    media volume --stream 4 --set 1 2>/dev/null
    media volume --stream 10 --set 1 2>/dev/null
    media dispatch mute 2>/dev/null
    echo schedutil > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>/dev/null
    echo schedutil > /sys/devices/system/cpu/cpufreq/policy4/scaling_governor 2>/dev/null
    echo 512 > /sys/block/sda/queue/read_ahead_kb 2>/dev/null
    echo reload > /proc/s9_serial 2>/dev/null
    ensure_usb_adb_alive
    sync_ghost_identity_stores
    sanitize_packages_and_timezone
    sync_stealth_proxy
    dump_proxy_rule_snapshot
    G_AID=$(grep -E '^android_id=' /efs/ghost.conf 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
    if [ -n "$G_AID" ]; then
        settings put secure android_id "$G_AID" 2>/dev/null
    fi

    # Block background Wi-Fi & BLE scanning (prevents nearby BSSID leaks)
    settings put global wifi_scan_always_enabled 0 2>/dev/null
    settings put global ble_scan_always_enabled 0 2>/dev/null
    settings put global wifi_scan_throttle_enabled 1 2>/dev/null
    settings put global wifi_verbose_logging_enabled 0 2>/dev/null

    # Revoke Location permissions from target shopping & tracking apps
    for rpkg in com.shopee.vn com.shopee.id com.shopee.my com.shopee.ph com.shopee.th com.shopee.sg com.shopee.tw com.shopee.br com.zhiliaoapp.musically com.ss.android.ugc.trill com.tiktokshop.seller; do
        pm revoke "$rpkg" android.permission.ACCESS_FINE_LOCATION 2>/dev/null
        pm revoke "$rpkg" android.permission.ACCESS_COARSE_LOCATION 2>/dev/null
        pm revoke "$rpkg" android.permission.ACCESS_BACKGROUND_LOCATION 2>/dev/null
    done

    # Ensure DeviceIdService is active & enabled
    pm enable com.samsung.android.deviceidservice 2>/dev/null
    pm enable com.samsung.android.deviceidservice/.DeviceIdService 2>/dev/null
    am startservice -a com.samsung.android.deviceidservice.action.GET_DEVICE_ID com.samsung.android.deviceidservice/.DeviceIdService 2>/dev/null || true

    # Un-freeze GMS Telemetry, Ads, Chimera, Consent & Measurement services (resolves API_DISABLED / statusCode=17)
    pm enable com.google.android.gms 2>/dev/null
    pm enable com.google.android.gms/.chimera.GmsApiService 2>/dev/null
    pm enable com.google.android.gms/com.google.android.gms.ads.identifier.service.AdvertisingIdService 2>/dev/null
    pm enable com.google.android.gms/com.google.android.gms.common.telemetry.service.TelemetryService 2>/dev/null
    pm enable com.google.android.gms/com.google.android.gms.common.telemetry.TelemetryService 2>/dev/null
    pm enable com.google.android.gms/com.google.android.gms.common.telemetry.service.ClientTelemetryChimeraService 2>/dev/null
    pm enable com.google.android.gms/com.google.android.gms.common.telemetry.service.ClientTelemetryService 2>/dev/null
    pm enable com.google.android.gms/com.google.android.gms.onboardingconsent.api.ConsentManagerApiService 2>/dev/null
    pm enable com.google.android.gms/com.google.android.gms.onboardingconsent.service.ConsentManagerConfigMigratorChimeraService 2>/dev/null
    pm enable com.google.android.gms/com.google.android.gms.measurement.service.MeasurementBrokerService 2>/dev/null
    pm enable com.google.android.gms/com.google.android.gms.measurement.AppMeasurementService 2>/dev/null
    pm enable com.google.android.gms/com.google.android.gms.chimera.GmsIntentOperationService 2>/dev/null

    # Configure location & consent global/secure settings
    settings put secure location_mode 3 2>/dev/null
    settings put secure network_location_opt_in 1 2>/dev/null
    settings put global google_play_services_package com.google.android.gms 2>/dev/null

    # Grant necessary permissions to GMS
    pm grant com.google.android.gms android.permission.INTERNET 2>/dev/null
    pm grant com.google.android.gms android.permission.ACCESS_NETWORK_STATE 2>/dev/null
    pm grant com.google.android.gms android.permission.ACCESS_WIFI_STATE 2>/dev/null
    pm grant com.google.android.gms android.permission.READ_PHONE_STATE 2>/dev/null
    pm grant com.google.android.gms android.permission.ACCESS_FINE_LOCATION 2>/dev/null
    pm grant com.google.android.gms android.permission.ACCESS_COARSE_LOCATION 2>/dev/null
    pm grant com.google.android.gms android.permission.BODY_SENSORS 2>/dev/null
    pm grant com.google.android.gms android.permission.ACTIVITY_RECOGNITION 2>/dev/null
    
    # Launch background Stealth Proxy guardian daemon detached from init service cgroup
    for sp in /data/adb/s9_proxy/stealth_proxy.sh /data/adb/stealth_proxy.sh /system/bin/stealth_proxy.sh; do
        if [ -x "$sp" ] || [ -f "$sp" ]; then
            if ! pgrep -f "stealth_proxy.sh daemon" >/dev/null 2>&1; then
                (
                    echo $$ > /acct/cgroup.procs 2>/dev/null
                    echo $$ > /dev/cpuset/cgroup.procs 2>/dev/null
                    exec /system/bin/sh "$sp" daemon >/dev/null 2>&1
                ) &
            fi
            break
        fi
    done

    # Watchdog loop detached from init service cgroup
    (
        echo $$ > /acct/cgroup.procs 2>/dev/null
        echo $$ > /dev/cpuset/cgroup.procs 2>/dev/null
        for t in 5 10 15 20 30 45 60 90; do
            sleep $t
            ensure_usb_adb_alive
            sync_persistent_clock
            sanitize_packages_and_timezone
            settings put global device_provisioned 1 2>/dev/null
            settings put secure user_setup_complete 1 2>/dev/null
            settings put secure sec_setupwizard_complete 1 2>/dev/null
            settings put secure tv_user_setup_complete 1 2>/dev/null
            settings put secure navigation_mode 0 2>/dev/null
            settings put global adb_enabled 0 2>/dev/null
            settings put global development_settings_enabled 0 2>/dev/null
            if [ -f /proc/s9_serial ]; then
                echo reload > /proc/s9_serial 2>/dev/null
            fi
            ensure_usb_adb_alive
            if [ "$t" = "5" ] || [ "$t" = "10" ] || [ "$t" = "20" ]; then
                for sp in /data/adb/s9_proxy/stealth_proxy.sh /data/adb/stealth_proxy.sh /system/bin/stealth_proxy.sh; do
                    if [ -x "$sp" ] || [ -f "$sp" ]; then
                        /system/bin/sh "$sp" auto >/dev/null 2>&1
                        break
                    fi
                done
            fi
            if [ "$t" = "20" ]; then
                dump_proxy_rule_snapshot
            fi
        done
    ) &
    exit 0
fi

# 1. Boost CPU (both Exynos 9810 clusters) & UFS Storage I/O during boot
echo performance > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>/dev/null
echo performance > /sys/devices/system/cpu/cpufreq/policy4/scaling_governor 2>/dev/null
echo 2048 > /sys/block/sda/queue/read_ahead_kb 2>/dev/null
echo 0 > /sys/block/sda/queue/iostats 2>/dev/null

# 2. Always ensure Headless ADB keys exist
mkdir -p /data/misc/adb
if [ -f /system/etc/adb_keys ] && [ ! -s /data/misc/adb/adb_keys ]; then
    cp -f /system/etc/adb_keys /data/misc/adb/adb_keys
fi
chown 1000:2000 /data/misc/adb /data/misc/adb/adb_keys 2>/dev/null
chmod 2750 /data/misc/adb 2>/dev/null
chmod 0640 /data/misc/adb/adb_keys 2>/dev/null

# 3. Always ensure Direct Boot DE/CE & App Data directories exist for user 0 (only runs at post-fs-data)
provision_direct_boot_dirs

# 4. Detect Fresh Format Data / Wipe (missing settings_global.xml or empty dalvik-cache)
if [ ! -f /data/system/users/0/settings_global.xml ] || [ ! -d /data/dalvik-cache/arm64 ]; then
    # Unpack pre-compiled uncompressed dalvik-cache seed (~1.2s at 650MB/s UFS speed!)
    if [ -f /system/etc/fastboot_dalvik.tar ] && [ ! -d /data/dalvik-cache/arm64 ]; then
        tar -xf /system/etc/fastboot_dalvik.tar -C / 2>/dev/null
        restorecon -R /data/dalvik-cache 2>/dev/null
    elif [ -f /system/etc/fastboot_dalvik.tar.gz ] && [ ! -d /data/dalvik-cache/arm64 ]; then
        tar -xzf /system/etc/fastboot_dalvik.tar.gz -C / 2>/dev/null
        restorecon -R /data/dalvik-cache 2>/dev/null
    fi

    # Create Direct Boot DE/CE directories and pre-provision settings
    provision_direct_boot_dirs
    scatter_package_install_times

    if [ ! -f /data/system/users/0/settings_global.xml ]; then
        cat << 'EOF' > /data/system/users/0/settings_global.xml
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<settings version="182">
  <setting id="1" name="device_provisioned" value="1" package="android" defaultValue="1" defaultSysSet="true" />
  <setting id="2" name="adb_enabled" value="0" package="android" defaultValue="0" defaultSysSet="true" />
  <setting id="3" name="stay_on_while_plugged_in" value="7" package="android" defaultValue="7" defaultSysSet="true" />
  <setting id="4" name="window_animation_scale" value="0.0" package="android" defaultValue="0.0" defaultSysSet="true" />
  <setting id="5" name="transition_animation_scale" value="0.0" package="android" defaultValue="0.0" defaultSysSet="true" />
  <setting id="6" name="animator_duration_scale" value="0.0" package="android" defaultValue="0.0" defaultSysSet="true" />
  <setting id="7" name="development_settings_enabled" value="0" package="android" defaultValue="0" defaultSysSet="true" />
  <setting id="8" name="hide_error_dialogs" value="1" package="android" defaultValue="1" defaultSysSet="true" />
  <setting id="9" name="zen_mode" value="2" package="android" defaultValue="2" defaultSysSet="true" />
</settings>
EOF
    fi

    if [ ! -f /data/system/users/0/settings_secure.xml ]; then
        G_AID=$(grep -E '^android_id=' /efs/ghost.conf 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
        [ -z "$G_AID" ] && G_AID="84b92c17f09a3e41"
        cat << EOF > /data/system/users/0/settings_secure.xml
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<settings version="182">
  <setting id="1" name="user_setup_complete" value="1" package="android" defaultValue="1" defaultSysSet="true" />
  <setting id="2" name="sec_setupwizard_complete" value="1" package="android" defaultValue="1" defaultSysSet="true" />
  <setting id="3" name="tv_user_setup_complete" value="1" package="android" defaultValue="1" defaultSysSet="true" />
  <setting id="4" name="lockscreen.disabled" value="1" package="android" defaultValue="1" defaultSysSet="true" />
  <setting id="5" name="navigation_mode" value="0" package="android" defaultValue="0" defaultSysSet="true" />
  <setting id="6" name="android_id" value="${G_AID}" package="android" defaultValue="${G_AID}" defaultSysSet="true" />
</settings>
EOF
    fi

    if [ ! -f /data/system/users/0/settings_system.xml ]; then
        cat << 'EOF' > /data/system/users/0/settings_system.xml
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<settings version="182">
  <setting id="1" name="screen_off_timeout" value="1800000" package="android" defaultValue="1800000" defaultSysSet="true" />
  <setting id="2" name="mode_ringer" value="0" package="android" defaultValue="0" defaultSysSet="true" />
  <setting id="3" name="volume_music" value="0" package="android" defaultValue="0" defaultSysSet="true" />
  <setting id="4" name="volume_ring" value="0" package="android" defaultValue="0" defaultSysSet="true" />
  <setting id="5" name="volume_system" value="0" package="android" defaultValue="0" defaultSysSet="true" />
  <setting id="6" name="volume_voice" value="0" package="android" defaultValue="0" defaultSysSet="true" />
  <setting id="7" name="volume_alarm" value="0" package="android" defaultValue="0" defaultSysSet="true" />
  <setting id="8" name="volume_notification" value="0" package="android" defaultValue="0" defaultSysSet="true" />
  <setting id="9" name="volume_bluetooth_sco" value="0" package="android" defaultValue="0" defaultSysSet="true" />
  <setting id="10" name="volume_a11y" value="0" package="android" defaultValue="0" defaultSysSet="true" />
  <setting id="11" name="sound_effects_enabled" value="0" package="android" defaultValue="0" defaultSysSet="true" />
  <setting id="12" name="dtmf_tone" value="0" package="android" defaultValue="0" defaultSysSet="true" />
  <setting id="13" name="lockscreen_sounds_enabled" value="0" package="android" defaultValue="0" defaultSysSet="true" />
  <setting id="14" name="haptic_feedback_enabled" value="0" package="android" defaultValue="0" defaultSysSet="true" />
</settings>
EOF
    fi

    chmod 600 /data/system/users/0/settings_*.xml 2>/dev/null
    chown 1000:1000 /data/system/users/0/settings_*.xml 2>/dev/null
    chcon u:object_r:system_data_file:s0 /data/data 2>/dev/null
fi

if [ -f /data/system/users/0/settings_global.xml ]; then
    sed -i '/name="adb_enabled"/s/value="[^"]*"/value="0"/g; /name="adb_enabled"/s/defaultValue="[^"]*"/defaultValue="0"/g' /data/system/users/0/settings_global.xml 2>/dev/null
    sed -i '/name="development_settings_enabled"/s/value="[^"]*"/value="0"/g; /name="development_settings_enabled"/s/defaultValue="[^"]*"/defaultValue="0"/g' /data/system/users/0/settings_global.xml 2>/dev/null
fi

sync_ghost_identity_stores
sync_stealth_proxy
dump_proxy_rule_snapshot

