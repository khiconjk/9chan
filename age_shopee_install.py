import subprocess, re, time

SERIAL = "192.168.1.130:5555"

# Calculate 12 days ago
cur_s = int(time.time())
# Target: ~12 days ago
aged_ms = 1790739980000
aged_hex = hex(aged_ms)[2:]

print(f"[*] Setting Shopee install time to {aged_hex} (12 days ago)...")

# 1. Patch packages.xml
cmd_pull1 = ['adb', '-s', SERIAL, 'pull', '/data/system/packages.xml', 'packages_local.xml']
subprocess.run(cmd_pull1, check=True)
with open('packages_local.xml', 'r', encoding='utf-8') as f:
    c1 = f.read()

# Replace ft and ut for com.shopee.vn
c1_mod = re.sub(r'(<package name="com\.shopee\.vn"[^>]*?ft=")[^"]*("[^>]*?ut=")[^"]*(")', rf'\g<1>{aged_hex}\g<2>{aged_hex}\g<3>', c1)
with open('packages_local.xml', 'w', encoding='utf-8') as f:
    f.write(c1_mod)
cmd_push1 = ['adb', '-s', SERIAL, 'push', 'packages_local.xml', '/data/system/packages.xml']
subprocess.run(cmd_push1, check=True)

# 2. Patch package-restrictions.xml
cmd_pull2 = ['adb', '-s', SERIAL, 'pull', '/data/system/users/0/package-restrictions.xml', 'restrictions_local.xml']
subprocess.run(cmd_pull2, check=True)
with open('restrictions_local.xml', 'r', encoding='utf-8') as f:
    c2 = f.read()

c2_mod = re.sub(r'(<pkg name="com\.shopee\.vn"[^>]*first-install-time=")[^"]*(")', rf'\g<1>{aged_hex}\g<2>', c2)
with open('restrictions_local.xml', 'w', encoding='utf-8') as f:
    f.write(c2_mod)
cmd_push2 = ['adb', '-s', SERIAL, 'push', 'restrictions_local.xml', '/data/system/users/0/package-restrictions.xml']
subprocess.run(cmd_push2, check=True)

# 3. Restart zygote so PackageManager reloads the aged install times
print("[*] Soft-restarting zygote...")
subprocess.run(['adb', '-s', SERIAL, 'shell', 'setprop ctl.restart zygote'])
time.sleep(10)

# 4. Verify
res = subprocess.run(['adb', '-s', SERIAL, 'shell', 'dumpsys package com.shopee.vn | grep -E "firstInstallTime|lastUpdateTime"'], capture_output=True, text=True)
print("[+] Verification:")
print(res.stdout)
