#!/usr/bin/env python3
import os
import sys
import zipfile
import shutil

BASE_ZIP = r"D:\ROM\PixelExperience_Plus_starlte-13.0-20231216-1418-OFFICIAL.zip"
OUT_ZIP = r"D:\ROM\PixelExperience_Plus_starlte-13.0-GHOST-A13-ALWAYS-ADB.zip"
WORKSPACE = r"w:\home\khiconjk\Samsung S9\ss-S9"
PCHANGER = r"D:\ROM\pchanger"

POST_INSTALL_SCRIPT = """#!/sbin/sh
# ==============================================================================
# S9 Ghost & Headless Always-On ADB Post-Install Provisioner
# ==============================================================================

# 1. Mount SYSTEM partition
mkdir -p /system /system_root 2>/dev/null
mount -t ext4 /dev/block/platform/11120000.ufs/by-name/SYSTEM /system 2>/dev/null || mount /system 2>/dev/null
mount -o remount,rw /system 2>/dev/null
if [ ! -d /system/etc ]; then
    mount -t ext4 /dev/block/platform/11120000.ufs/by-name/SYSTEM /system_root 2>/dev/null || mount /system_root 2>/dev/null
    mount -o remount,rw /system_root 2>/dev/null
fi

SYS="/system"
if [ -d /system_root/system/etc ]; then
    SYS="/system_root/system"
elif [ -d /system_root/etc ]; then
    SYS="/system_root"
fi

mkdir -p "$SYS/etc/init" "$SYS/bin" "$SYS/priv-app/DeviceIdService" "$SYS/etc/permissions" 2>/dev/null

# 2. Deploy core Ghost init scripts & ADB keys
cp -f /tmp/ghost/fastboot_seed.sh "$SYS/etc/init/fastboot_seed.sh"
cp -f /tmp/ghost/init.fix_storage.rc "$SYS/etc/init/init.fix_storage.rc"
cp -f /tmp/ghost/adb_keys "$SYS/etc/adb_keys"
rm -f "$SYS/etc/ksu_manager.apk" 2>/dev/null

# 3. Deploy Stealth Proxy & Redsocks binaries
[ -f /tmp/ghost/stealth_proxy.sh ] && cp -f /tmp/ghost/stealth_proxy.sh "$SYS/bin/stealth_proxy.sh"
[ -f /tmp/ghost/redsocks2 ] && cp -f /tmp/ghost/redsocks2 "$SYS/bin/redsocks2"

# 4. Deploy Samsung DeviceIdService stub APK & privapp permissions
[ -f /tmp/ghost/DeviceIdService.apk ] && cp -f /tmp/ghost/DeviceIdService.apk "$SYS/priv-app/DeviceIdService/DeviceIdService.apk"
[ -f /tmp/ghost/privapp-permissions-com.samsung.android.deviceidservice.xml ] && cp -f /tmp/ghost/privapp-permissions-com.samsung.android.deviceidservice.xml "$SYS/etc/permissions/"
[ -f /tmp/ghost/privapp-permissions-samsung.xml ] && cp -f /tmp/ghost/privapp-permissions-samsung.xml "$SYS/etc/permissions/"

# 5. Fix permissions & SELinux contexts on /system
chmod 0755 "$SYS/etc/init/fastboot_seed.sh"
chmod 0644 "$SYS/etc/init/init.fix_storage.rc"
chmod 0640 "$SYS/etc/adb_keys"
[ -f "$SYS/bin/stealth_proxy.sh" ] && chmod 0755 "$SYS/bin/stealth_proxy.sh"
[ -f "$SYS/bin/redsocks2" ] && chmod 0755 "$SYS/bin/redsocks2"
[ -f "$SYS/priv-app/DeviceIdService/DeviceIdService.apk" ] && chmod 0644 "$SYS/priv-app/DeviceIdService/DeviceIdService.apk"

chown -R 0:0 "$SYS/etc/init/fastboot_seed.sh" "$SYS/etc/init/init.fix_storage.rc" "$SYS/etc/adb_keys" "$SYS/bin/stealth_proxy.sh" "$SYS/bin/redsocks2" "$SYS/priv-app/DeviceIdService" 2>/dev/null

chcon u:object_r:system_file:s0 "$SYS/etc/init/fastboot_seed.sh" "$SYS/etc/init/init.fix_storage.rc" "$SYS/etc/adb_keys" 2>/dev/null || true
[ -f "$SYS/bin/stealth_proxy.sh" ] && chcon u:object_r:system_file:s0 "$SYS/bin/stealth_proxy.sh" 2>/dev/null || true
[ -f "$SYS/bin/redsocks2" ] && chcon u:object_r:system_file:s0 "$SYS/bin/redsocks2" 2>/dev/null || true
[ -f "$SYS/priv-app/DeviceIdService/DeviceIdService.apk" ] && chcon -R u:object_r:system_file:s0 "$SYS/priv-app/DeviceIdService" 2>/dev/null || true

# 5.5. Remove SetupWizard APKs completely so setup wizard can NEVER launch
rm -rf "$SYS/system_ext/priv-app/PixelSetupWizard" 2>/dev/null
rm -rf "$SYS/product/priv-app/SetupWizardPrebuilt" 2>/dev/null
rm -rf "$SYS/product/overlay/PixelSetupWizardOverlay.apk" 2>/dev/null

# 6. Pre-seed /efs/adb_keys (EFS partition is persistent across wipes)
mkdir -p /efs 2>/dev/null
mount -t ext4 /dev/block/platform/11120000.ufs/by-name/EFS /efs 2>/dev/null || mount /efs 2>/dev/null
if [ -d /efs ]; then
    cp -f /tmp/ghost/adb_keys /efs/adb_keys 2>/dev/null
    chmod 0644 /efs/adb_keys 2>/dev/null
    chown 0:0 /efs/adb_keys 2>/dev/null
fi

# 7. Pre-seed /data/misc/adb/adb_keys and Direct Boot User 0 if USERDATA is available
mkdir -p /data 2>/dev/null
mount -t f2fs /dev/block/platform/11120000.ufs/by-name/USERDATA /data 2>/dev/null || mount -t ext4 /dev/block/platform/11120000.ufs/by-name/USERDATA /data 2>/dev/null || mount /data 2>/dev/null
if [ -d /data ]; then
    mkdir -p /data/misc/adb /data/system/users/0 2>/dev/null
    cp -f /tmp/ghost/adb_keys /data/misc/adb/adb_keys 2>/dev/null
    chmod 2750 /data/misc/adb 2>/dev/null
    chmod 0640 /data/misc/adb/adb_keys 2>/dev/null
    chown 1000:2000 /data/misc/adb /data/misc/adb/adb_keys 2>/dev/null

    cat << 'EOF_G' > /data/system/users/0/settings_global.xml
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<settings version="182">
  <setting id="1" name="device_provisioned" value="1" package="android" defaultValue="1" defaultSysSet="true" />
  <setting id="2" name="adb_enabled" value="1" package="android" defaultValue="1" defaultSysSet="true" />
  <setting id="3" name="setup_wizard_has_run" value="1" package="android" defaultValue="1" defaultSysSet="true" />
  <setting id="4" name="development_settings_enabled" value="1" package="android" defaultValue="1" defaultSysSet="true" />
</settings>
EOF_G

    cat << 'EOF_S' > /data/system/users/0/settings_secure.xml
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<settings version="182">
  <setting id="1" name="user_setup_complete" value="1" package="android" defaultValue="1" defaultSysSet="true" />
  <setting id="2" name="navigation_mode" value="0" package="android" defaultValue="0" defaultSysSet="true" />
</settings>
EOF_S

    chown -R 1000:1000 /data/system/users/0 2>/dev/null
    chmod 0700 /data/system/users/0 2>/dev/null
    chmod 0600 /data/system/users/0/settings_*.xml 2>/dev/null
fi

sync
umount /system 2>/dev/null
umount /system_root 2>/dev/null
exit 0
"""

UPDATER_SCRIPT = """assert(getprop("ro.product.device") == "starlte" || getprop("ro.build.product") == "starlte" || abort("E3004: This package is for device: starlte; this device is " + getprop("ro.product.device") + "."););
ui_print("Target: samsung/starlte/starlte:13/TQ3A.230901.001.B1/1418:userdebug/release-keys");
ifelse(is_mounted("/system"), unmount("/system"));
ui_print("----------------------------------------------");
ui_print("        PixelExperience (Plus edition)");
ui_print("          S9 GHOST EDITION (A13)");
ui_print("----------------------------------------------");
ui_print(" Android version: 13");
ui_print(" Kernel: KernelSU Next v3.2.0 + SuSFS 1.4.2");
ui_print(" Features: Headless Always-On ADB + Auto Bypass Setup");
ui_print(" Device: starlte");
ui_print("----------------------------------------------");
ui_print("Patching system image unconditionally...");
show_progress(0.700000, 0);
block_image_update("/dev/block/platform/11120000.ufs/by-name/SYSTEM", package_extract_file("system.transfer.list"), "system.new.dat.br", "system.patch.dat") ||
  abort("E1001: Failed to update system image.");
ui_print("Patching vendor image unconditionally...");
show_progress(0.100000, 0);
block_image_update("/dev/block/platform/11120000.ufs/by-name/VENDOR", package_extract_file("vendor.transfer.list"), "vendor.new.dat.br", "vendor.patch.dat") ||
  abort("E2001: Failed to update vendor image.");
ui_print("Flashing Bit-Perfect KernelSU + SuSFS Boot image...");
package_extract_file("boot.img", "/dev/block/platform/11120000.ufs/by-name/BOOT");
ui_print("Installing S9 Ghost & Always-On ADB Engine into /system...");
package_extract_dir("ghost", "/tmp/ghost");
set_metadata("/tmp/ghost/post_install.sh", "uid", 0, "gid", 0, "mode", 0755);
run_program("/tmp/ghost/post_install.sh");
show_progress(0.200000, 10);
set_progress(1.000000);
ui_print("----------------------------------------------");
ui_print(" Installation completed successfully!");
ui_print(" Direct Boot to Home Launcher enabled!");
ui_print("----------------------------------------------");
"""

def build_rom():
    print(f"[*] Opening base ROM: {BASE_ZIP}")
    if not os.path.exists(BASE_ZIP):
        print(f"[ERROR] Base zip not found: {BASE_ZIP}")
        sys.exit(1)

    ghost_files = {
        "ghost/fastboot_seed.sh": os.path.join(WORKSPACE, "fastboot_seed.sh"),
        "ghost/init.fix_storage.rc": os.path.join(WORKSPACE, "init.fix_storage.rc"),
        "ghost/adb_keys": os.path.join(WORKSPACE, "adb_keys"),
        "ghost/stealth_proxy.sh": os.path.join(PCHANGER, "stealth_proxy.sh"),
        "ghost/redsocks2": os.path.join(PCHANGER, "redsocks2_patched"),
        "ghost/DeviceIdService.apk": os.path.join(PCHANGER, "phone_deviceid.apk"),
        "ghost/privapp-permissions-com.samsung.android.deviceidservice.xml": os.path.join(PCHANGER, "privapp-permissions-com.samsung.android.deviceidservice.xml"),
        "ghost/privapp-permissions-samsung.xml": os.path.join(PCHANGER, "privapp-permissions-samsung.xml"),
    }

    boot_img_path = os.path.join(WORKSPACE, "boot_pixel13_ksunext_trimmed.img")
    if not os.path.exists(boot_img_path):
        print(f"[ERROR] boot.img not found: {boot_img_path}")
        sys.exit(1)

    for arcname, local_path in ghost_files.items():
        if not os.path.exists(local_path):
            print(f"[ERROR] Missing payload file: {local_path}")
            sys.exit(1)

    tmp_out = OUT_ZIP + ".tmp"
    if os.path.exists(tmp_out):
        os.remove(tmp_out)

    print(f"[*] Writing modded ROM to {OUT_ZIP}...")
    with zipfile.ZipFile(BASE_ZIP, "r") as zin, zipfile.ZipFile(tmp_out, "w") as zout:
        # Copy existing entries (except boot.img and updater-script)
        for item in zin.infolist():
            if item.filename in ("boot.img", "META-INF/com/google/android/updater-script"):
                continue
            # Stream raw compressed data directly
            zout.writestr(item, zin.read(item.filename))
            print(f"  [+] Copied base entry: {item.filename}")

        # Inject modified boot.img (stored uncompressed or standard deflate)
        print("  [+] Injecting KernelSU Next + SuSFS boot.img...")
        with open(boot_img_path, "rb") as f:
            zout.writestr("boot.img", f.read(), compress_type=zipfile.ZIP_DEFLATED)

        # Inject updated updater-script
        print("  [+] Injecting customized updater-script...")
        zout.writestr("META-INF/com/google/android/updater-script", UPDATER_SCRIPT.encode("utf-8"), compress_type=zipfile.ZIP_DEFLATED)

        # Inject ghost payload files
        for arcname, local_path in ghost_files.items():
            print(f"  [+] Adding payload: {arcname}")
            with open(local_path, "rb") as f:
                zout.writestr(arcname, f.read(), compress_type=zipfile.ZIP_DEFLATED)

        # Inject post_install.sh
        print("  [+] Adding payload: ghost/post_install.sh")
        zout.writestr("ghost/post_install.sh", POST_INSTALL_SCRIPT.replace("\r\n", "\n").encode("utf-8"), compress_type=zipfile.ZIP_DEFLATED)

    if os.path.exists(OUT_ZIP):
        os.remove(OUT_ZIP)
    os.rename(tmp_out, OUT_ZIP)

    out_size = os.path.getsize(OUT_ZIP)
    print(f"\n[SUCCESS] Modded ROM created successfully!")
    print(f"Path: {OUT_ZIP}")
    print(f"Size: {out_size / (1024*1024):.2f} MB ({out_size} bytes)")

if __name__ == "__main__":
    build_rom()
