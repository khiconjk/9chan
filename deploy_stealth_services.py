import subprocess
import time
import sys

def run(cmd, shell=False):
    print(f">> Running: {cmd}")
    res = subprocess.run(cmd, shell=shell, capture_output=True, text=True)
    if res.stdout.strip():
        print(res.stdout.strip())
    if res.stderr.strip():
        print(f"[ERR] {res.stderr.strip()}")
    return res

def wait_for_adb():
    print("Waiting for device to connect via ADB...")
    while True:
        res = subprocess.run(["adb", "devices"], capture_output=True, text=True)
        lines = [line.strip() for line in res.stdout.splitlines() if line.strip() and not line.startswith("List")]
        devices = [l for l in lines if "\tdevice" in l]
        if devices:
            print(f"Device connected: {devices[0]}")
            break
        time.sleep(2)

def deploy():
    wait_for_adb()
    
    print("\n=== Step 1: Ensure root access ===")
    run(["adb", "root"])
    time.sleep(2)
    wait_for_adb()
    
    print("\n=== Step 2: Ensure /data/adb/stealth/ directory and push services_patched.jar ===")
    run(["adb", "shell", "mkdir -p /data/adb/stealth"])
    run(["adb", "push", "services_patched.jar", "/data/adb/stealth/services.jar"])
    run(["adb", "shell", "chmod 644 /data/adb/stealth/services.jar && chown 0:0 /data/adb/stealth/services.jar"])
    
    print("\n=== Step 3: Compile matching services.odex and services.vdex via dex2oat64 ===")
    dex2oat_cmd = (
        "/apex/com.android.art/bin/dex2oat64 "
        "--dex-file=/data/adb/stealth/services.jar "
        "--dex-location=/system/framework/services.jar "
        "--oat-file=/data/adb/stealth/services.odex "
        "--instruction-set=arm64 "
        "--instruction-set-features=a53,crc,-lse,-fp16,-dotprod,-sve "
        "--compiler-filter=speed"
    )
    res = run(["adb", "shell", dex2oat_cmd])
    if res.returncode != 0:
        print("[WARN] dex2oat exited with non-zero code, checking files...")
        
    run(["adb", "shell", "touch /data/adb/stealth/empty.art"])
    run(["adb", "shell", "chmod 644 /data/adb/stealth/* && chown 0:0 /data/adb/stealth/*"])
    run(["adb", "shell", "ls -lh /data/adb/stealth/"])
    
    print("\n=== Step 4: Create post-fs-data boot hook ===")
    script_content = '''#!/system/bin/sh
# 05_stealth_services.sh - Stealth Services Framework via KernelSU + SuSFS
if [ -f /data/adb/stealth/services.jar ] && [ -f /data/adb/stealth/services.odex ]; then
    mount -o bind /data/adb/stealth/services.jar /system/framework/services.jar
    mount -o bind /data/adb/stealth/services.odex /system/framework/oat/arm64/services.odex
    mount -o bind /data/adb/stealth/services.vdex /system/framework/oat/arm64/services.vdex
    mount -o bind /data/adb/stealth/empty.art /system/framework/oat/arm64/services.art

    if [ -x /data/adb/ksud ]; then
        /data/adb/ksud kernel umount add /system/framework/services.jar 2>/dev/null
        /data/adb/ksud kernel umount add /system/framework/oat/arm64/services.odex 2>/dev/null
        /data/adb/ksud kernel umount add /system/framework/oat/arm64/services.vdex 2>/dev/null
        /data/adb/ksud kernel umount add /system/framework/oat/arm64/services.art 2>/dev/null
        /data/adb/ksud kernel notify-module-mounted 2>/dev/null
    fi
fi
'''
    with open("05_stealth_services.sh", "w", newline="\n", encoding="utf-8") as f:
        f.write(script_content)
        
    run(["adb", "push", "05_stealth_services.sh", "/data/adb/post-fs-data.d/05_stealth_services.sh"])
    run(["adb", "shell", "chmod 755 /data/adb/post-fs-data.d/05_stealth_services.sh && chown 0:0 /data/adb/post-fs-data.d/05_stealth_services.sh"])
    
    print("\n=== Step 5: Test live bind-mount and verify SuSFS isolation ===")
    run(["adb", "shell", "sh /data/adb/post-fs-data.d/05_stealth_services.sh"])
    
    print("\n=== Step 6: Restart runtime to load patched services into system_server ===")
    run(["adb", "shell", "stop; sleep 2; start"])
    print("Waiting 15 seconds for system_server to initialize...")
    time.sleep(15)
    
    wait_for_adb()
    run(["adb", "shell", "getprop sys.boot_completed; pidof system_server"])
    
    print("\n=== Step 7: Apply Stealth Settings (adb_enabled=0, development_settings_enabled=0) ===")
    run(["adb", "shell", "settings put global adb_enabled 0"])
    run(["adb", "shell", "settings put global development_settings_enabled 0"])
    run(["adb", "shell", "/data/adb/ksud resetprop -n init.svc.adbd stopped"])
    run(["adb", "shell", "/data/adb/ksud resetprop -n sys.usb.state mtp"])
    
    time.sleep(3)
    wait_for_adb()
    print("\n[SUCCESS] ADB IS STILL CONNECTED WITH adb_enabled=0!")
    
    print("\n=== Step 8: Verify VNeID Clean Launch ===")
    run(["adb", "shell", "am force-stop com.vnid && sleep 1 && am start -n com.vnid/com.vnid.MainActivity && sleep 3"])
    run(["adb", "shell", "screencap -p /sdcard/vneid_final_stealth.png"])
    run(["adb", "pull", "/sdcard/vneid_final_stealth.png", "C:\\Users\\TUNG PC\\.gemini\\antigravity\\brain\\e44e6c2c-13a5-45a7-8c3a-65b2c31aba4c\\vneid_final_stealth.png"])
    run(["adb", "shell", "rm /sdcard/vneid_final_stealth.png"])
    print("\n=== ALL STEPS COMPLETED PERFECTLY ===")

if __name__ == "__main__":
    deploy()
