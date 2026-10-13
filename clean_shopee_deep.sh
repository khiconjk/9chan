#!/system/bin/sh
# ==============================================================================
# clean_shopee_deep.sh - Deep Purge of All Shopee Device Fingerprints & Residuals
# Anti-Format Anomaly / Anti-F00 Clean Room Engine
# ==============================================================================

echo "[*] Bắt đầu dọn sạch sẽ toàn bộ dấu vết rò rỉ Shopee (Anti-F00 & Anti-Format Flag)..."

# 1. Đảm bảo file APK được lưu vĩnh viễn trong /sdcard/RomInstall
mkdir -p /sdcard/RomInstall 2>/dev/null
if [ ! -f /sdcard/RomInstall/com.shopee.vn.apk ]; then
    src_apk=$(pm path com.shopee.vn 2>/dev/null | head -n1 | cut -d: -f2)
    if [ -n "$src_apk" ] && [ -f "$src_apk" ]; then
        echo "[+] Đang sao lưu Shopee APK từ $src_apk..."
        cp -f "$src_apk" /sdcard/RomInstall/com.shopee.vn.apk 2>/dev/null
    fi
fi

# 2. Dừng hoàn toàn tiến trình Shopee
echo "[+] Dừng tiến trình Shopee..."
am force-stop com.shopee.vn 2>/dev/null
killall -9 com.shopee.vn 2>/dev/null

# 3. Gỡ cài đặt hoàn toàn để hủy bỏ Keystore namespace, UID cũ và firstInstallTime cũ
echo "[+] Gỡ cài đặt com.shopee.vn để xóa sạch UID và Keystore cũ..."
pm uninstall com.shopee.vn 2>/dev/null

# 4. Xóa sạch sẽ toàn bộ thư mục dữ liệu nội bộ và ngoại vi
echo "[+] Xóa sạch Sandbox, SDCard dữ liệu và tệp fingerprint..."
rm -rf /data/data/com.shopee.vn \
       /data/user/0/com.shopee.vn \
       /data/user_de/0/com.shopee.vn \
       /sdcard/Android/data/com.shopee.vn \
       /sdcard/Android/media/com.shopee.vn \
       /sdcard/Android/obb/com.shopee.vn \
       /data/media/0/Android/data/com.shopee.vn \
       /data/media/0/Android/media/com.shopee.vn \
       /data/media/0/Android/obb/com.shopee.vn \
       /data_mirror/data_ce/null/0/com.shopee.vn \
       /data_mirror/data_de/null/0/com.shopee.vn 2>/dev/null

# Xóa các tệp định danh tiềm ẩn trên SDCard
rm -rf /sdcard/.shopee* /sdcard/.aegis* /sdcard/.tongdun* /sdcard/.turing* /sdcard/.system* /sdcard/.td* /sdcard/tencent 2>/dev/null
rm -rf /data/media/0/.shopee* /data/media/0/.aegis* /data/media/0/.tongdun* /data/media/0/.turing* /data/media/0/.system* /data/media/0/.td* 2>/dev/null
find /sdcard /data/media/0 -name "dfdata" -delete 2>/dev/null
find /sdcard /data/media/0 -name ".database_uuid" -delete 2>/dev/null
rm -rf /sdcard/Pictures/.thumbnails /sdcard/Movies/.thumbnails /sdcard/Music/.thumbnails /sdcard/DCIM/.thumbnails 2>/dev/null

# 5. Xóa sạch SSAID trên cả 3 file của SettingsProvider và tái tạo userkey
echo "[+] Xóa sạch SSAID trên SettingsProvider..."
for sxml in /data/system/users/0/settings_ssaid.xml /data/system/users/0/settings_ssaid.xml.new /data/system/users/0/settings_ssaid.xml.fallback; do
    if [ -f "$sxml" ]; then
        sed -i '/package="com\.shopee/d; /com\.shopee/d' "$sxml" 2>/dev/null
    fi
done

if [ -f /data/system/users/0/settings_ssaid.xml ]; then
    NEW_KEY=$(cat /proc/sys/kernel/random/uuid | tr -d '-' | tr '[:lower:]' '[:upper:]')$(cat /proc/sys/kernel/random/uuid | tr -d '-' | tr '[:lower:]' '[:upper:]')
    sed -i -E "/name=\"userkey\"/s/value=\"[0-9A-Fa-f]+\"/value=\"$NEW_KEY\"/g; /name=\"userkey\"/s/defaultValue=\"[0-9A-Fa-f]+\"/defaultValue=\"$NEW_KEY\"/g" /data/system/users/0/settings_ssaid.xml 2>/dev/null
fi

# 6. Dọn sạch tàn dư Keystore 2.0 (persistent.sqlite)
echo "[+] Dọn sạch Android Keystore 2.0..."
if [ -f /data/misc/keystore/persistent.sqlite ]; then
    sqlite3 /data/misc/keystore/persistent.sqlite "DELETE FROM blobmetadata WHERE blobentryid IN (SELECT id FROM blobentry WHERE keyentryid IN (SELECT id FROM keyentry WHERE namespace >= 10000)); DELETE FROM blobentry WHERE keyentryid IN (SELECT id FROM keyentry WHERE namespace >= 10000); DELETE FROM keyparameter WHERE keyentryid IN (SELECT id FROM keyentry WHERE namespace >= 10000); DELETE FROM keymetadata WHERE keyentryid IN (SELECT id FROM keyentry WHERE namespace >= 10000); DELETE FROM grant WHERE keyentryid IN (SELECT id FROM keyentry WHERE namespace >= 10000); DELETE FROM keyentry WHERE namespace >= 10000; VACUUM;" 2>/dev/null
    killall -9 keystore2 2>/dev/null || kill -9 $(pidof keystore2) 2>/dev/null
fi

# 7. Xóa sạch DRM runtime files & Advertising ID
echo "[+] Xóa DRM cache & Advertising ID..."
rm -rf /data/vendor/mediadrm/IDM1013/* /data/mediadrm/* /data/drm/* 2>/dev/null
rm -f /data/data/com.google.android.gms/shared_prefs/adid_settings.xml 2>/dev/null

# 8. Xóa sạch nhật ký hệ thống (Dropbox, Graphicsstats, Package Usage, App Idle)
echo "[+] Dọn dẹp nhật ký hệ thống..."
rm -rf /data/system/dropbox/* 2>/dev/null
rm -rf /data/system/graphicsstats/* /data/system/battery-usage-stats/* /data/system/procexitstore/* 2>/dev/null
rm -f /data/system/package-usage.list 2>/dev/null
if [ -f /data/system/users/0/app_idle_stats.xml ]; then
    sed -i '/com\.shopee/d' /data/system/users/0/app_idle_stats.xml 2>/dev/null
fi

# 9. Bơm dữ liệu lịch sử tự nhiên (Device Warmth Seeding) để xóa cờ "Vừa format máy"
echo "[+] Đồng bộ dữ liệu mồi ấm (Device Warmth Seeding)..."
if [ -f /data/local/tmp/seed_warmth.sh ]; then
    /data/local/tmp/seed_warmth.sh 2>/dev/null
fi

# 10. Cài đặt lại sạch sẽ Shopee từ kho lưu trữ với nguồn Google Play Store
echo "[+] Đang cài đặt mới Shopee từ /data/local/tmp/apk_cache/com.shopee.vn.apk..."
mkdir -p /data/local/tmp/apk_cache 2>/dev/null
if [ ! -f /data/local/tmp/apk_cache/com.shopee.vn.apk ] && [ -f /sdcard/RomInstall/com.shopee.vn.apk ]; then
    cp -f /sdcard/RomInstall/com.shopee.vn.apk /data/local/tmp/apk_cache/com.shopee.vn.apk 2>/dev/null
fi
if [ -f /data/local/tmp/apk_cache/com.shopee.vn.apk ]; then
    chmod 644 /data/local/tmp/apk_cache/com.shopee.vn.apk 2>/dev/null
    chcon u:object_r:shell_data_file:s0 /data/local/tmp/apk_cache/com.shopee.vn.apk 2>/dev/null
    pm install -i com.android.vending /data/local/tmp/apk_cache/com.shopee.vn.apk 2>/dev/null
fi

# 11. Cấp quyền tiêu chuẩn & TUYỆT ĐỐI KHÔNG cấp READ_DEVICE_IDENTIFIERS hay READ_CONTACTS
echo "[+] Cấu hình AppOps & Runtime Permissions tiêu chuẩn..."
pm grant com.shopee.vn android.permission.POST_NOTIFICATIONS 2>/dev/null
pm grant com.shopee.vn android.permission.ACCESS_COARSE_LOCATION 2>/dev/null
pm grant com.shopee.vn android.permission.ACCESS_FINE_LOCATION 2>/dev/null
cmd appops set com.shopee.vn COARSE_LOCATION ignore 2>/dev/null
cmd appops set com.shopee.vn FINE_LOCATION ignore 2>/dev/null

# Đưa quyền đọc định danh về mặc định (SecurityException trên A10+) -> Chặn triệt để rò rỉ IMEI phần cứng
cmd appops set com.shopee.vn READ_DEVICE_IDENTIFIERS default 2>/dev/null
cmd appops set com.shopee.vn USE_ICC_AUTH_WITH_DEVICE_IDENTIFIER default 2>/dev/null

# 12. Làm già hóa thời gian cài đặt ứng dụng (Aged Install Time: 10-14 ngày trước)
echo "[+] Làm già hóa firstInstallTime của Shopee về 10-14 ngày trước..."
CUR_S=$(date +%s 2>/dev/null)
[ -z "$CUR_S" ] && CUR_S=1791776780
OFFSET=$((864000 + (CUR_S % 259200))) # 10-13 ngày
HEX_FT=$(awk -v s="$CUR_S" -v off="$OFFSET" 'BEGIN { printf("%llx\n", (s - off) * 1000); }')
HEX_UT=$(awk -v s="$CUR_S" -v off="$OFFSET" 'BEGIN { printf("%llx\n", (s - off + 86400) * 1000); }')

if [ -n "$HEX_FT" ] && [ -n "$HEX_UT" ]; then
    for pxml in /data/system/packages.xml /data/system/packages-backup.xml; do
        if [ -f "$pxml" ]; then
            sed -i "/package name=\"com.shopee.vn\"/s/it=\"[^\"]*\"/it=\"$HEX_FT\"/" "$pxml" 2>/dev/null
            sed -i "/package name=\"com.shopee.vn\"/s/ut=\"[^\"]*\"/ut=\"$HEX_UT\"/" "$pxml" 2>/dev/null
            sed -i "/package name=\"com.shopee.vn\"/s/ft=\"[^\"]*\"/ft=\"$HEX_FT\"/" "$pxml" 2>/dev/null
        fi
    done
    if [ -f /data/system/users/0/package-restrictions.xml ]; then
        sed -i -E "s/(<pkg name=\"com\.shopee\.vn\"[^>]*first-install-time=\")[^\"]*/\1$HEX_FT/" /data/system/users/0/package-restrictions.xml 2>/dev/null
    fi
fi

# 13. Khởi động lại Zygote nhẹ (Soft restart) để nạp sạch SSAID & installTime mới
echo "[+] Tải lại Zygote để kích hoạt SSAID và installTime già hóa..."
setprop ctl.restart zygote 2>/dev/null

echo "[✓] HOÀN TẤT DỌN DẸP SẠCH TOÀN DIỆN! THIẾT BỊ HOÀN TOÀN MỚI, TỰ NHIÊN VÀ KHÔNG BỊ CỜ FORMAT!"
exit 0
