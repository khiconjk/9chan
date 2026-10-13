import subprocess
import re
import datetime

REMOTE_PATH = "/data/system/users/0/package-restrictions.xml"
LOCAL_PATH = "package_restrictions_local.xml"
OUT_PATH = "package_restrictions_aged.xml"

subprocess.run(["adb", "pull", REMOTE_PATH, LOCAL_PATH], check=True)

with open(LOCAL_PATH, "r", encoding="utf-8") as f:
    content = f.read()

# Target user packages to age
# 2026-07-20 10:15:00 = 1784517300000 -> 19f7d850f20
# 2026-07-25 14:20:00 = 1784964000000 -> 19f98252900
# 2026-08-01 10:00:00 = 1785553200000 -> 19fbb43a380
# 2026-06-25 10:00:00 = 1782356400000 -> 19efca82380 (for google sync / feedback)

targets = {
    "com.shopee.vn": "19f7d850f20",
    "com.ss.android.ugc.trill": "19f98252900",
    "flar2.devcheck": "19fbb43a380",
    "com.google.android.feedback": "19efca82380",
    "com.google.android.syncadapters.calendar": "19efca82380",
    "com.google.android.safetycore": "19efca82380"
}

modified_content = content
for pkg, new_hex in targets.items():
    pattern = rf'(<pkg name="{re.escape(pkg)}"[^>]*?first-install-time=")([^"]*)(")'
    match = re.search(pattern, modified_content)
    if match:
        old_hex = match.group(2)
        try:
            old_dt = datetime.datetime.fromtimestamp(int(old_hex, 16) / 1000)
            new_dt = datetime.datetime.fromtimestamp(int(new_hex, 16) / 1000)
        except Exception:
            old_dt = old_hex
            new_dt = new_hex
        print(f"[{pkg}] first-install-time: {old_hex} ({old_dt}) -> {new_hex} ({new_dt})")
        modified_content = re.sub(pattern, rf'\g<1>{new_hex}\g<3>', modified_content, count=1)
    else:
        print(f"[{pkg}] NOT found in package-restrictions.xml")

with open(OUT_PATH, "w", encoding="utf-8") as f:
    f.write(modified_content)

print("\nApplying to device...")
subprocess.run(["adb", "shell", "stop"], check=True)
subprocess.run(["adb", "push", OUT_PATH, REMOTE_PATH], check=True)
subprocess.run(["adb", "shell", f"chmod 660 {REMOTE_PATH}; chown system:system {REMOTE_PATH}"], check=True)
subprocess.run(["adb", "shell", "start"], check=True)
print("Framework restarted!")
