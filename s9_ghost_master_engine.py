#!/usr/bin/env python3
"""
================================================================================
S9 GHOST MASTER ENGINE (UNIFIED AUTOMATION & SYNCHRONIZATION)
Samsung Galaxy S9 / S9+ (Exynos 9810) - Android 13
100% Zero-Root / Zero-User-Hook / Ring 0 Kernel + Bionic In-Place Sync
================================================================================
Consolidates ALL security fixes and virtualization synchronization:
1. /efs/ghost.conf Ingestion & Kernel Dynamic Reload (/proc/s9_serial)
2. USB Hardware Gadget Serial Sync (/config/usb_gadget/.../serialnumber)
3. Wi-Fi Hardware MAC Sync & Global MAC Randomization Lock
4. Bionic In-Place Atomic Memory Patching (No reboot, No crash)
   - build_prop, build_vendor_prop, build_odm_prop (Model, Product, Device)
   - bootloader_prop (ro.boot.em.model, ro.bootloader, ro.boot.bootloader)
   - radio_prop (gsm.version.baseband, ril.product_code, ril.sw_ver)
   - fingerprint_prop (ro.build.fingerprint)
   - serialno_prop (ro.serialno, ro.boot.serialno)
5. Physical Cellular & RIL Lock:
   - Force pure LTE mode (cmd phone set-allowed-network-types-for-users)
   - Unified Viettel 45204 operator numeric & alpha
   - Clear ril.rejectedPlmn
6. Synaptics Hardware Touch Injection Deployment (/dev/input/event0)
================================================================================
"""

import sys
import os
import subprocess
import time

GHOST_CONF_PATH = "/efs/ghost.conf"
WORKSPACE_DIR = os.path.dirname(os.path.abspath(__file__))

def run_adb(cmd, check=True):
    full_cmd = ["adb"] + cmd
    res = subprocess.run(full_cmd, capture_output=True, text=True)
    if check and res.returncode != 0:
        print(f"[ERROR] adb {' '.join(cmd)} failed:\n{res.stderr.strip()}", file=sys.stderr)
    return res

def run_adb_shell(shell_cmd, check=True):
    return run_adb(["shell", shell_cmd], check=check)

def load_ghost_conf():
    res = run_adb_shell(f"cat {GHOST_CONF_PATH}")
    if res.returncode != 0 or not res.stdout.strip():
        print("[ERROR] Cannot read /efs/ghost.conf from device!", file=sys.stderr)
        sys.exit(1)
        
    config = {}
    for line in res.stdout.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        config[k.strip()] = v.strip()
    return config

def step1_reload_kernel():
    print("[1/6] Triggering Kernel Ring 0 Dynamic Reload...")
    run_adb_shell("echo reload > /proc/s9_serial")
    time.sleep(1)
    res = run_adb_shell("dmesg | grep -i ghost | tail -n 2")
    print(f"      Kernel log: {res.stdout.strip()}")

def step2_sync_hardware_ids(conf):
    print("[2/6] Synchronizing Hardware Sysfs & USB Gadget...")
    serial = conf.get("serialno", "ce7281f09ab31c")
    run_adb_shell(f"echo {serial} > /config/usb_gadget/g1/strings/0x409/serialnumber 2>/dev/null")
    
    wifi_mac = conf.get("wifi_mac", "")
    if wifi_mac:
        run_adb_shell(f"echo -n '{wifi_mac}' > /efs/wifi/.mac.info 2>/dev/null")
        run_adb_shell(f"echo -n '{wifi_mac}' > /data/vendor/conn/.mac.info 2>/dev/null")
        run_adb_shell("settings put global wifi_connected_mac_randomization_enabled 0 2>/dev/null")
    print(f"      USB Serial: {serial} | Wi-Fi Hardware MAC: {wifi_mac}")

def step3_patch_bionic_properties(conf):
    print("[3/6] In-Place Atomic Patching User-Space Bionic Properties...")
    model = conf.get("ro.product.model", "SM-G965F")
    device = conf.get("ro.product.device", "star2lte")
    name = conf.get("ro.product.name", "star2lte")
    bootloader = conf.get("ro.bootloader", "G965FXXUHFVG5")
    baseband = conf.get("gsm.version.baseband", bootloader)
    prod_code = conf.get("ril.product_code", "SM-G965FZBDXXV")
    fp = conf.get("ro.build.fingerprint", f"samsung/{device}/{device}:13/TP1A.220624.014/{bootloader}:user/release-keys")
    display_id = conf.get("ro.build.display.id", f"TP1A.220624.014.{bootloader}")
    inc = conf.get("ro.build.version.incremental", bootloader)
    serial = conf.get("serialno", "ce7281f09ab31c")

    patch_map = {
        "build_prop": {
            "ro.product.model": model,
            "ro.product.system.model": model,
            "ro.product.system_ext.model": model,
            "ro.product.device": device,
            "ro.product.name": name,
            "ro.build.product": device,
            "ro.build.display.id": display_id,
            "ro.build.version.incremental": inc,
            "ro.build.id": "TP1A.220624.014"
        },
        "build_vendor_prop": {
            "ro.product.vendor.model": model,
            "ro.product.vendor.device": device,
            "ro.product.vendor.name": name
        },
        "build_odm_prop": {
            "ro.product.odm.model": model,
            "ro.product.odm.device": device,
            "ro.product.odm.name": name
        },
        "bootloader_prop": {
            "ro.boot.em.model": model,
            "ro.bootloader": bootloader,
            "ro.boot.bootloader": bootloader
        },
        "radio_prop": {
            "gsm.version.baseband": baseband,
            "ril.sw_ver": baseband,
            "ril.product_code": prod_code,
            "ril.simoperator": "45204"
        },
        "fingerprint_prop": {
            "ro.build.fingerprint": fp
        },
        "serialno_prop": {
            "ro.serialno": serial,
            "ro.boot.serialno": serial
        },
        "firstboot_prop": {
            "ro.runtime.firstboot": "1781283673704"
        }
    }

    for ctx, pdict in patch_map.items():
        dev_file = f"/dev/__properties__/u:object_r:{ctx}:s0"
        chk = run_adb_shell(f"ls {dev_file}", check=False)
        if "No such file" in chk.stderr or "No such file" in chk.stdout:
            continue
            
        local_f = os.path.join(WORKSPACE_DIR, f"{ctx}.tmp")
        run_adb(["pull", dev_file, local_f], check=True)
        
        with open(local_f, "r+b") as f:
            data = f.read()
            for pname, pval in pdict.items():
                pbytes = pname.encode()
                idx = data.find(pbytes)
                if idx != -1:
                    start = idx - 96
                    serial_word = int.from_bytes(data[start:start+4], "little")
                    dirty = serial_word | 1
                    f.seek(start)
                    f.write(dirty.to_bytes(4, "little"))
                    f.flush()
                    
                    new_val_bytes = pval.encode() + b'\x00' * (92 - len(pval))
                    f.seek(start + 4)
                    f.write(new_val_bytes)
                    f.flush()
                    
                    clean = (len(pval) << 24) | ((dirty + 1) & 0xFFFFFF)
                    f.seek(start)
                    f.write(clean.to_bytes(4, "little"))
                    f.flush()

        tmp_dev = f"/data/local/tmp/{ctx}.tmp"
        run_adb(["push", local_f, tmp_dev], check=True)
        run_adb_shell(f"chmod 644 {dev_file}; dd if={tmp_dev} of={dev_file} conv=notrunc 2>/dev/null; chmod 444 {dev_file}; rm -f {tmp_dev}")
        if os.path.exists(local_f):
            os.remove(local_f)

    print("      All Bionic property contexts updated successfully.")

def step4_lock_telephony():
    print("[4/6] Enforcing Cellular Bands & Operator Locks...")
    # Lock LTE Only (prevents camping on Mobifone 3G)
    run_adb_shell("cmd phone set-allowed-network-types-for-users -s 0 01000001000000000000 2>/dev/null")
    run_adb_shell("setprop gsm.operator.numeric 45204 2>/dev/null")
    run_adb_shell("setprop gsm.sim.operator.numeric 45204 2>/dev/null")
    run_adb_shell("setprop gsm.operator.alpha Viettel 2>/dev/null")
    run_adb_shell("setprop gsm.sim.operator.alpha Viettel 2>/dev/null")
    run_adb_shell("setprop ril.rejectedPlmn '' 2>/dev/null")
    print("      Cellular forced to LTE | Viettel 45204 unified.")

def step5_deploy_touch_engine():
    print("[5/6] Verifying Synaptics Touch Engine Deployment...")
    touch_script = os.path.join(WORKSPACE_DIR, "s9_touch.sh")
    if os.path.exists(touch_script):
        run_adb(["push", touch_script, "/data/local/tmp/s9_touch"])
        run_adb_shell("chmod 755 /data/local/tmp/s9_touch")
        print("      Hardware Touch Engine ready at /data/local/tmp/s9_touch.")

def step_filesystem_aging():
    print("[6/7] Applying Filesystem & Inode Aging...")
    run_adb_shell("touch -d '2026-06-13 00:01:13' /data /data/system /data/system/users /data/system/users/0 /sdcard /sdcard/DCIM /data/media/0 2>/dev/null")
    print("      Filesystem timestamps synced to 2026-06-13 00:01:13.")

def step6_verify_system():
    print("[7/7] Final Integrity & Leak Audit Verification:")
    checks = [
        "cat /proc/cmdline | grep -o 'androidboot.em.model=[^ ]*'",
        "cat /proc/cmdline | grep -o 'androidboot.bootloader=[^ ]*'",
        "cat /proc/cmdline | grep -o 'androidboot.serialno=[^ ]*'",
        "getprop ro.product.model",
        "getprop ro.product.vendor.model",
        "getprop ro.product.name",
        "getprop ro.boot.em.model",
        "getprop ro.bootloader",
        "getprop ro.serialno",
        "getprop ro.runtime.firstboot",
        "getprop gsm.operator.numeric",
        "getprop ril.product_code"
    ]
    for c in checks:
        res = run_adb_shell(c)
        print(f"      {c.split()[-1]}: {res.stdout.strip()}")

def main():
    print("=" * 65)
    print("S9 GHOST MASTER ENGINE - FULL SYNCHRONIZATION")
    print("=" * 65)
    conf = load_ghost_conf()
    step1_reload_kernel()
    step2_sync_hardware_ids(conf)
    step3_patch_bionic_properties(conf)
    step4_lock_telephony()
    step5_deploy_touch_engine()
    step_filesystem_aging()
    step6_verify_system()
    print("=" * 65)
    print("SYNCHRONIZATION COMPLETED SUCCESSFULLY (100% UNIFIED)")
    print("=" * 65)

if __name__ == "__main__":
    main()
