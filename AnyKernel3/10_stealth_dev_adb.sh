#!/system/bin/sh
# 10_stealth_dev_adb.sh - Stealth Developer Options & ADB Properties Guardian
# Powered by KernelSU Next + SuSFS + ksud resetprop

# 1. Hide Developer Options in SettingsProvider
settings put global development_settings_enabled 0 2>/dev/null

# 2. Synchronize settings_global.xml
SETTINGS_XML="/data/system/users/0/settings_global.xml"
if [ -f "$SETTINGS_XML" ]; then
    sed -i '/name="development_settings_enabled"/s/value="[^"]*"/value="0"/g; /name="development_settings_enabled"/s/defaultValue="[^"]*"/defaultValue="0"/g' "$SETTINGS_XML" 2>/dev/null
fi

# 3. Mask ADB & Debug markers in shared memory Prefix Trie via ksud resetprop
if [ -x /data/adb/ksud ]; then
    # Fake adbd daemon status to stopped
    /data/adb/ksud resetprop -n init.svc.adbd stopped 2>/dev/null
    
    # Remove sensitive adb tracking markers
    /data/adb/ksud resetprop -n -d init.svc_debug_pid.adbd 2>/dev/null
    /data/adb/ksud resetprop -n -d ro.boottime.adbd 2>/dev/null
    /data/adb/ksud resetprop -n -d service.adb.root 2>/dev/null
    
    # Mask USB configuration properties to pure MTP
    /data/adb/ksud resetprop -n sys.usb.config mtp 2>/dev/null
    /data/adb/ksud resetprop -n sys.usb.state mtp 2>/dev/null
    /data/adb/ksud resetprop -n -p persist.sys.usb.config mtp 2>/dev/null
    /data/adb/ksud resetprop -n persist.sys.usb.q_config mtp 2>/dev/null
    /data/adb/ksud resetprop -n persist.service.adb.enable 0 2>/dev/null
    
    # Enforce standard Android security properties
    /data/adb/ksud resetprop -n ro.debuggable 0 2>/dev/null
    /data/adb/ksud resetprop -n ro.secure 1 2>/dev/null
    /data/adb/ksud resetprop -n ro.build.type user 2>/dev/null
    /data/adb/ksud resetprop -n ro.build.tags release-keys 2>/dev/null
    /data/adb/ksud resetprop -n ro.adb.secure 1 2>/dev/null
fi

# 7. Disable IPv6 to prevent hardware MAC and router MAC leaks
sysctl -w net.ipv6.conf.all.disable_ipv6=1 2>/dev/null
sysctl -w net.ipv6.conf.default.disable_ipv6=1 2>/dev/null
sysctl -w net.ipv6.conf.wlan0.disable_ipv6=1 2>/dev/null
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null
echo 1 > /proc/sys/net/ipv6/conf/default/disable_ipv6 2>/dev/null
echo 1 > /proc/sys/net/ipv6/conf/wlan0/disable_ipv6 2>/dev/null
ip -6 addr flush dev wlan0 2>/dev/null

exit 0
