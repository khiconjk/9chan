import subprocess, json, datetime, sys, os

sys.stdout.reconfigure(encoding='utf-8')

def sh(cmd):
    target = os.environ.get("ANDROID_SERIAL", "192.168.1.130:5555")
    res = subprocess.run(["adb", "-s", target, "shell", cmd], capture_output=True, text=True)
    return res.stdout.strip()

print("="*60)
print("AUDIT: KIEM NGHIEM LAO HOA THIET BI (AGED PROFILE VERIFICATION)")
print("="*60)

# 1. First Boot & Uptime
firstboot_raw = sh("getprop ro.runtime.firstboot")
if firstboot_raw.isdigit():
    fb_sec = int(firstboot_raw) / 1000
    fb_time = datetime.datetime.fromtimestamp(fb_sec)
    print(f"[1] ro.runtime.firstboot: {firstboot_raw} -> {fb_time}")
else:
    print(f"[1] ro.runtime.firstboot: {firstboot_raw}")

uptime_raw = sh("cat /proc/uptime")
btime_raw = sh("cat /proc/stat | grep btime")
print(f"[2] /proc/uptime: {uptime_raw} | {btime_raw}")

# 2. Filesystem & User 0 creation timestamps
user0_time = sh("stat -c '%y' /data/system/users/0 2>/dev/null")
print(f"[3] /data/system/users/0 timestamp: {user0_time}")

data_time = sh("stat -c '%y' /data/system 2>/dev/null")
print(f"[4] /data/system timestamp: {data_time}")

root_data_time = sh("stat -c '%y' /data 2>/dev/null")
print(f"[5] /data root timestamp: {root_data_time}")

# 3. Settings & SSAID timestamps
ssaid_stat = sh("stat -c '%y' /data/system/users/0/settings_ssaid.xml 2>/dev/null")
print(f"[6] settings_ssaid.xml timestamp: {ssaid_stat}")

# 4. App First Install Times from PackageManager
for target in ["com.shopee.vn", "com.ss.android.ugc.trill", "flar2.devcheck"]:
    dump_out = sh(f"dumpsys package {target} | grep -E 'firstInstallTime|lastUpdateTime'")
    lines = [l.strip() for l in dump_out.splitlines() if l.strip()]
    info = " | ".join(lines)
    print(f"[7] Package {target} -> {info}")

# 5. Call log, Contacts, SMS
calls_cnt = sh("content query --uri content://call_log/calls 2>/dev/null | wc -l")
sms_cnt = sh("content query --uri content://sms 2>/dev/null | wc -l")
contacts_cnt = sh("content query --uri content://com.android.contacts/contacts 2>/dev/null | wc -l")
print(f"[8] Content Providers -> Calls: {calls_cnt}, SMS: {sms_cnt}, Contacts: {contacts_cnt}")

# 6. MediaStore (Photos, Downloads, Audio)
photos_cnt = sh("content query --uri content://media/external/images/media 2>/dev/null | wc -l")
dcim_photos = sh("ls -1 /sdcard/DCIM/Camera 2>/dev/null | wc -l")
screenshots = sh("ls -1 /sdcard/Pictures/Screenshots 2>/dev/null | wc -l")
downloads_cnt = sh("ls -1 /sdcard/Download 2>/dev/null | wc -l")
print(f"[9] MediaStore Images: {photos_cnt} (Camera: {dcim_photos}, Screenshots: {screenshots}, Downloads: {downloads_cnt})")

# 7. Wi-Fi Configured Networks
wifi_cnt = sh("grep -c '<WifiConfiguration>' /data/misc/apexdata/com.android.wifi/WifiConfigStore.xml 2>/dev/null")
print(f"[10] Saved Wi-Fi Networks: {wifi_cnt}")

# 8. Storage Free Space & Total Inodes
df_data = sh("df -h /data | tail -n 1")
print(f"[11] /data disk usage: {df_data}")

# 9. Battery Stats & History
batt_dump = sh("dumpsys batterystats --daily | grep -E 'Current start time|Next min deadline'")
print(f"[12] BatteryStats daily: {batt_dump}")

# 10. Google Accounts
acc_out = sh("dumpsys account | grep -E 'Accounts: [0-9]+' | head -n 2")
print(f"[13] Google Accounts: {acc_out}")
