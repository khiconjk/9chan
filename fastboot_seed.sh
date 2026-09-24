#!/system/bin/sh
# Fast First-Boot & Headless Always-On ADB Seed Engine (Runs at post-fs-data & boot_completed as root)

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
}

if [ -f /data/local/tmp/fix.sh ]; then
    mv -f /data/local/tmp/fix.sh /data/local/tmp/fix.sh.run
    /system/bin/sh /data/local/tmp/fix.sh.run
    rm -f /data/local/tmp/fix.sh.run
    exit 0
fi

if [ "$1" = "--fix" ]; then
    provision_direct_boot_dirs
    exit 0
fi

if [ "$1" = "--boot-completed" ]; then
    locksettings set-disabled true 2>/dev/null
    settings put global device_provisioned 1 2>/dev/null
    settings put secure user_setup_complete 1 2>/dev/null
    settings put secure sec_setupwizard_complete 1 2>/dev/null
    settings put secure tv_user_setup_complete 1 2>/dev/null
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
    
    # Watchdog loop to guarantee 3 navigation buttons & anti-RILD overwrite
    (
        for t in 5 10 15 20 30 45 60 90; do
            sleep $t
            settings put global device_provisioned 1 2>/dev/null
            settings put secure user_setup_complete 1 2>/dev/null
            settings put secure sec_setupwizard_complete 1 2>/dev/null
            settings put secure tv_user_setup_complete 1 2>/dev/null
            settings put global adb_enabled 0 2>/dev/null
            settings put global development_settings_enabled 0 2>/dev/null
            if [ -f /proc/s9_serial ]; then
                echo reload > /proc/s9_serial 2>/dev/null
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

    if [ ! -f /data/system/users/0/settings_global.xml ]; then
        cat << 'EOF' > /data/system/users/0/settings_global.xml
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<settings version="182">
  <setting id="1" name="device_provisioned" value="1" package="android" defaultValue="1" defaultSysSet="true" />
  <setting id="2" name="adb_enabled" value="1" package="android" defaultValue="1" defaultSysSet="true" />
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
        cat << 'EOF' > /data/system/users/0/settings_secure.xml
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<settings version="182">
  <setting id="1" name="user_setup_complete" value="1" package="android" defaultValue="1" defaultSysSet="true" />
  <setting id="2" name="sec_setupwizard_complete" value="1" package="android" defaultValue="1" defaultSysSet="true" />
  <setting id="3" name="tv_user_setup_complete" value="1" package="android" defaultValue="1" defaultSysSet="true" />
  <setting id="4" name="lockscreen.disabled" value="1" package="android" defaultValue="1" defaultSysSet="true" />
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
