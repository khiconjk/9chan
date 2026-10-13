#!/system/bin/sh
stop

# 1. Clear dfdata and Shopee data
rm -rf /data/media/0/Android/data/com.shopee.vn
rm -rf /sdcard/Android/data/com.shopee.vn
find /sdcard /data/media/0 -name 'dfdata' -delete 2>/dev/null
rm -rf /data/data/com.shopee.vn/*

# 2. Generate brand new SSAID & userkey
NEW_SSAID=$(cat /proc/sys/kernel/random/uuid | tr -d '-' | cut -c 1-16)
NEW_USERKEY=$(cat /proc/sys/kernel/random/uuid | tr -d '-' | tr '[:lower:]' '[:upper:]')$(cat /proc/sys/kernel/random/uuid | tr -d '-' | tr '[:lower:]' '[:upper:]')

XML=/data/system/users/0/settings_ssaid.xml
if [ -f "$XML" ]; then
    # Replace userkey
    sed -i -E "s/name=\"userkey\" value=\"[0-9A-Fa-f]+\"/name=\"userkey\" value=\"$NEW_USERKEY\"/" "$XML"
    sed -i -E "s/defaultValue=\"[0-9A-Fa-f]+\" defaultSysSet=\"true\"/defaultValue=\"$NEW_USERKEY\" defaultSysSet=\"true\"/" "$XML"
    # Replace Shopee SSAID
    sed -i -E "s/value=\"[0-9a-f]{16}\" package=\"com\.shopee\.vn\" defaultValue=\"[0-9a-f]{16}\"/value=\"$NEW_SSAID\" package=\"com.shopee.vn\" defaultValue=\"$NEW_SSAID\"/" "$XML"
fi

start
sleep 5
echo "DONE NEW_SSAID=$NEW_SSAID"
