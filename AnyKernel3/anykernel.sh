### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=ss-S9 starlte Stock Android 10 VANILLA GHOST FULL (Ghost Uptime + Headless + Proxy Lockdown)
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=starlte
device.name2=starltexx
device.name3=starlteks
device.name4=SM-G960F
device.name5=SM-G960N
device.name6=star2lte
device.name7=star2ltexx
device.name8=SM-G965F
device.name9=crownlte
device.name10=crownltexx
device.name11=SM-N960F
supported.versions=10
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties


### AnyKernel install
## boot files attributes
boot_attributes() {
set_perm_recursive 0 0 755 644 $RAMDISK/*;
set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
} # end attributes

# boot shell variables
BLOCK=/dev/block/platform/11120000.ufs/by-name/BOOT;
IS_SLOT_DEVICE=0;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# boot install
dump_boot; # use split_boot to skip ramdisk unpack, e.g. for devices with init_boot ramdisk

# Patch ramdisk fstab: forceencrypt -> encryptable (keeps encryption flow working)
# and add ro.crypto.state=unencrypted to default.prop
for f in $RAMDISK/fstab* $RAMDISK/fstab.*; do
  if [ -f "$f" ]; then
    ui_print "  Patching ramdisk fstab: $(basename $f)...";
    # Change forceencrypt to encryptable (don't remove - Android needs the flag for proper boot)
    sed -i 's/forceencrypt=/encryptable=/g' "$f";
    # Remove fileencryption flags
    sed -i 's/fileencryption=[^,]*,//g' "$f";
    sed -i 's/fileencryption=[^,]*//g' "$f";
  fi
done

# Add ro.crypto.state=unencrypted to default.prop to prevent vold from encrypting
if [ -f "$RAMDISK/default.prop" ]; then
  if ! grep -q 'ro.crypto.state' "$RAMDISK/default.prop"; then
    ui_print "  Adding ro.crypto.state=unencrypted to default.prop...";
    echo "" >> "$RAMDISK/default.prop";
    echo "# Anti-forceencrypt: tell vold data is unencrypted" >> "$RAMDISK/default.prop";
    echo "ro.crypto.state=unencrypted" >> "$RAMDISK/default.prop";
  else
    ui_print "  Patching ro.crypto.state in default.prop...";
    sed -i 's/ro.crypto.state=.*/ro.crypto.state=unencrypted/g' "$RAMDISK/default.prop";
  fi
fi

# Install the Ghost post-fs-data hooks into the active Android system partition.
# The AnyKernel ramdisk overlay alone cannot provide /system/etc/init files.
ui_print " ";
ui_print "- Installing S9 Ghost init provisioning files...";
SYSTEM_BLOCK=/dev/block/platform/11120000.ufs/by-name/SYSTEM;
if [ ! -f "$AKHOME/fastboot_seed.sh" ] || [ ! -f "$AKHOME/init.fix_storage.rc" ] || \
   [ ! -f "$AKHOME/stealth_proxy.sh" ] || [ ! -f "$AKHOME/redsocks_patched" ] || \
   [ ! -f "$AKHOME/redsocks2_patched" ]; then
  abort "S9 Ghost init/proxy payload is incomplete in this ZIP.";
fi
if ! mount -o remount,rw /system 2>/dev/null; then
  mount /system 2>/dev/null || mount -t ext4 -o rw "$SYSTEM_BLOCK" /system 2>/dev/null || true;
  mount -o remount,rw /system 2>/dev/null || mount -o rw,remount /system 2>/dev/null || abort "Unable to mount /system read-write; Ghost init files were not installed.";
fi
if [ -d /system/etc ]; then
  SYSTEM_ETC=/system/etc;
elif [ -d /system_root/system/etc ]; then
  SYSTEM_ETC=/system_root/system/etc;
else
  abort "Android system /etc directory is unavailable.";
fi
SYSTEM_INIT_DIR="$SYSTEM_ETC/init";
SYSTEM_BIN_DIR="${SYSTEM_ETC%/etc}/bin";
mkdir -p "$SYSTEM_INIT_DIR" "$SYSTEM_BIN_DIR" || abort "Unable to create Ghost system directories.";
WRITE_TEST="$SYSTEM_INIT_DIR/.ak3-ghost-write-test";
touch "$WRITE_TEST" 2>/dev/null || abort "System partition is not writable; Ghost init files were not installed.";
rm -f "$WRITE_TEST";
rm -f "$SYSTEM_INIT_DIR/fastboot_seed.sh.orig" "$SYSTEM_INIT_DIR/fastboot_seed.sh~" \
      "$SYSTEM_INIT_DIR/init.fix_storage.rc.orig" "$SYSTEM_INIT_DIR/init.fix_storage.rc~" \
      "$SYSTEM_BIN_DIR/stealth_proxy.sh.orig" "$SYSTEM_BIN_DIR/stealth_proxy.sh~" \
      "$SYSTEM_BIN_DIR/redsocks.orig" "$SYSTEM_BIN_DIR/redsocks~" \
      "$SYSTEM_BIN_DIR/redsocks2.orig" "$SYSTEM_BIN_DIR/redsocks2~" 2>/dev/null;
cp -pf "$AKHOME/fastboot_seed.sh" "$SYSTEM_INIT_DIR/fastboot_seed.sh" || abort "Failed to install fastboot_seed.sh.";
cp -pf "$AKHOME/init.fix_storage.rc" "$SYSTEM_INIT_DIR/init.fix_storage.rc" || abort "Failed to install init.fix_storage.rc.";
cp -pf "$AKHOME/stealth_proxy.sh" "$SYSTEM_BIN_DIR/stealth_proxy.sh" || abort "Failed to install stealth_proxy.sh.";
cp -pf "$AKHOME/redsocks_patched" "$SYSTEM_BIN_DIR/redsocks" || abort "Failed to install redsocks.";
cp -pf "$AKHOME/redsocks2_patched" "$SYSTEM_BIN_DIR/redsocks2" || abort "Failed to install dual-stack redsocks2.";
chown 0:0 "$SYSTEM_INIT_DIR/fastboot_seed.sh" "$SYSTEM_INIT_DIR/init.fix_storage.rc" "$SYSTEM_BIN_DIR/stealth_proxy.sh" "$SYSTEM_BIN_DIR/redsocks" "$SYSTEM_BIN_DIR/redsocks2" "$SYSTEM_ETC/adb_keys" "$SYSTEM_ETC/fastboot_dalvik.tar" 2>/dev/null;
chmod 0700 "$SYSTEM_INIT_DIR/fastboot_seed.sh" "$SYSTEM_BIN_DIR/stealth_proxy.sh" "$SYSTEM_BIN_DIR/redsocks" "$SYSTEM_BIN_DIR/redsocks2";
chmod 0600 "$SYSTEM_INIT_DIR/init.fix_storage.rc" "$SYSTEM_ETC/adb_keys" "$SYSTEM_ETC/fastboot_dalvik.tar" 2>/dev/null;
restorecon "$SYSTEM_INIT_DIR/fastboot_seed.sh" "$SYSTEM_INIT_DIR/init.fix_storage.rc" "$SYSTEM_BIN_DIR/stealth_proxy.sh" "$SYSTEM_BIN_DIR/redsocks" "$SYSTEM_BIN_DIR/redsocks2" "$SYSTEM_ETC/adb_keys" "$SYSTEM_ETC/fastboot_dalvik.tar" 2>/dev/null;

# Clean stale bind-mount sources, snapshots, and world-readable files on /data and /efs
mount /data 2>/dev/null || mount -t ext4 -o rw /dev/block/platform/11120000.ufs/by-name/USERDATA /data 2>/dev/null || true;
mount /efs 2>/dev/null || mount -t ext4 -o rw /dev/block/platform/11120000.ufs/by-name/EFS /efs 2>/dev/null || true;
rm -rf /data/adb/fastboot_seed.sh /data/adb/stealth_proxy.rules.snapshot /data/adb/s9_proxy/stealth_proxy.rules.snapshot \
       /data/local/tmp/check_new_user.sh /data/local/tmp/dalvik-cache /data/local/tmp/fix.sh* \
       /data/local/tmp/ghost_* /data/local/tmp/stealth_proxy* /data/local/tmp/redsocks* 2>/dev/null;
for gf in /efs/ghost.conf /data/adb/s9_ghost.conf /data/system/ghost.conf.bak; do
  if [ -f "$gf" ]; then
    sed -i '/^[[:space:]]*#/d' "$gf" 2>/dev/null;
    chown 0:0 "$gf" 2>/dev/null;
    chmod 0600 "$gf" 2>/dev/null;
  fi
done
[ -f /efs/ghost_rtc.epoch ] && chown 0:0 /efs/ghost_rtc.epoch 2>/dev/null && chmod 0600 /efs/ghost_rtc.epoch 2>/dev/null;
if [ -d /data/adb ]; then
  cp -pf "$AKHOME/stealth_proxy.sh" /data/adb/stealth_proxy.sh 2>/dev/null;
  chown 0:2000 /data/adb 2>/dev/null;
  chmod 0710 /data/adb 2>/dev/null;
  chown 0:0 /data/adb/stealth_proxy.sh 2>/dev/null;
  chmod 0700 /data/adb/stealth_proxy.sh 2>/dev/null;
  mkdir -p /data/adb/s9_proxy 2>/dev/null;
  chown -R 0:2000 /data/adb/s9_proxy 2>/dev/null;
  chmod 0770 /data/adb/s9_proxy 2>/dev/null;
fi

# Clean /system/build.prop of Note 9 leftovers, test-keys, 2026 dates & serialno2
SYSTEM_BUILD_PROP="${SYSTEM_ETC%/etc}/build.prop";
if [ -f "$SYSTEM_BUILD_PROP" ]; then
  ui_print "  Harmonizing $SYSTEM_BUILD_PROP...";
  sed -i '/ro.pchanger/d' "$SYSTEM_BUILD_PROP";
  sed -i '/ro.boot.serialno2/d' "$SYSTEM_BUILD_PROP";
  sed -i 's/^ro.build.keys=.*/ro.build.keys=release-keys/g' "$SYSTEM_BUILD_PROP";
  sed -i 's/^ro.build.user=.*/ro.build.user=dpi/g' "$SYSTEM_BUILD_PROP";
  sed -i 's/^ro.build.host=.*/ro.build.host=SWDD5915/g' "$SYSTEM_BUILD_PROP";
  sed -i 's/^ro.build.product=.*/ro.build.product=starlte/g' "$SYSTEM_BUILD_PROP";
  sed -i 's/^net.bt.name=.*/net.bt.name=Android/g' "$SYSTEM_BUILD_PROP";
  sed -i 's/^ro.system.build.tags=.*/ro.system.build.tags=release-keys/g' "$SYSTEM_BUILD_PROP";
  sed -i 's/^ro.system.build.type=.*/ro.system.build.type=user/g' "$SYSTEM_BUILD_PROP";
  sed -i 's/^ro.build.tags=.*/ro.build.tags=release-keys/g' "$SYSTEM_BUILD_PROP";
  sed -i 's/^ro.build.type=.*/ro.build.type=user/g' "$SYSTEM_BUILD_PROP";
  sed -i 's/^ro.system.build.date=.*/ro.system.build.date=Tue Jul 12 18:30:00 KST 2022/g' "$SYSTEM_BUILD_PROP";
  sed -i 's/^ro.system.build.date.utc=.*/ro.system.build.date.utc=1657618200/g' "$SYSTEM_BUILD_PROP";
  sed -i 's/^ro.build.date=.*/ro.build.date=Tue Jul 12 18:30:00 KST 2022/g' "$SYSTEM_BUILD_PROP";
  sed -i 's/^ro.build.date.utc=.*/ro.build.date.utc=1657618200/g' "$SYSTEM_BUILD_PROP";
  chmod 0644 "$SYSTEM_BUILD_PROP";
fi
sync;
ui_print "  fastboot_seed/init hooks and dual-stack proxy runtime installed.";

write_boot; # use flash_boot to skip ramdisk repack, e.g. for devices with init_boot ramdisk
## end boot install

# Disable forced encryption & Samsung Knox services
ui_print " ";
ui_print "- Disabling forced encryption & Knox services...";
mount -o remount,rw /vendor 2>/dev/null || mount -o rw /dev/block/platform/11120000.ufs/by-name/VENDOR /vendor 2>/dev/null || mount -o rw /vendor 2>/dev/null;
if [ -d /vendor/etc ]; then
  for f in /vendor/etc/fstab* /vendor/etc/fstab.*; do
    if [ -f "$f" ]; then
      ui_print "  Patching $f...";
      sed -i 's/forceencrypt=footer,//g' "$f";
      sed -i 's/encryptable=footer,//g' "$f";
      sed -i 's/,forceencrypt=footer//g' "$f";
      sed -i 's/,encryptable=footer//g' "$f";
      sed -i 's/forceencrypt=footer//g' "$f";
      sed -i 's/encryptable=footer//g' "$f";
      sed -i 's/,length=-20480//g' "$f";
      sed -i 's/length=-20480,//g' "$f";
      sed -i 's/fileencryption=[^,]*,//g' "$f";
      sed -i 's/fileencryption=[^,]*//g' "$f";
      sed -i 's/errors=panic/errors=continue/g' "$f";
    fi
  done
  if [ -f /vendor/build.prop ]; then
    ui_print "  Harmonizing /vendor/build.prop...";
    sed -i 's/^ro.board.platform=.*/ro.board.platform=exynos5/g' /vendor/build.prop;
    sed -i 's/^ro.vendor.build.tags=.*/ro.vendor.build.tags=release-keys/g' /vendor/build.prop;
    sed -i 's/^ro.vendor.build.type=.*/ro.vendor.build.type=user/g' /vendor/build.prop;
    sed -i 's/^ro.bootimage.build.tags=.*/ro.bootimage.build.tags=release-keys/g' /vendor/build.prop;
    sed -i 's/^ro.bootimage.build.type=.*/ro.bootimage.build.type=user/g' /vendor/build.prop;
    sed -i 's/^ro.vendor.build.date=.*/ro.vendor.build.date=Tue Jul 12 18:30:00 KST 2022/g' /vendor/build.prop;
    sed -i 's/^ro.vendor.build.date.utc=.*/ro.vendor.build.date.utc=1657618200/g' /vendor/build.prop;
    sed -i 's/^ro.bootimage.build.date=.*/ro.bootimage.build.date=Tue Jul 12 18:30:00 KST 2022/g' /vendor/build.prop;
    sed -i 's/^ro.bootimage.build.date.utc=.*/ro.bootimage.build.date.utc=1657618200/g' /vendor/build.prop;
    sed -i 's/^security.securehw.available=.*/security.securehw.available=true/g' /vendor/build.prop;
    sed -i 's/^security.securenvm.available=.*/security.securenvm.available=true/g' /vendor/build.prop;
    chmod 0644 /vendor/build.prop;
  fi
  ui_print "  Vendor fstab & build.prop patched successfully.";
fi
umount /vendor 2>/dev/null;


## init_boot files attributes
#init_boot_attributes() {
#set_perm_recursive 0 0 755 644 $RAMDISK/*;
#set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
#} # end attributes

# init_boot shell variables
#BLOCK=init_boot;
#IS_SLOT_DEVICE=1;
#RAMDISK_COMPRESSION=auto;
#PATCH_VBMETA_FLAG=auto;

# reset for init_boot patching
#reset_ak;

# init_boot install
#dump_boot; # unpack ramdisk since it is the new first stage init ramdisk where overlay.d must go

#write_boot;
## end init_boot install


## vendor_kernel_boot shell variables
#BLOCK=vendor_kernel_boot;
#IS_SLOT_DEVICE=1;
#RAMDISK_COMPRESSION=auto;
#PATCH_VBMETA_FLAG=auto;

# reset for vendor_kernel_boot patching
#reset_ak;

# vendor_kernel_boot install
#split_boot; # skip unpack/repack ramdisk, e.g. for dtb on devices with hdr v4 and vendor_kernel_boot

#flash_boot;
## end vendor_kernel_boot install


## vendor_boot files attributes
#vendor_boot_attributes() {
#set_perm_recursive 0 0 755 644 $RAMDISK/*;
#set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
#} # end attributes

# vendor_boot shell variables
#BLOCK=vendor_boot;
#IS_SLOT_DEVICE=1;
#RAMDISK_COMPRESSION=auto;
#PATCH_VBMETA_FLAG=auto;

# reset for vendor_boot patching
#reset_ak;

# vendor_boot install
#dump_boot; # use split_boot to skip ramdisk unpack, e.g. for dtb on devices with hdr v4 but no vendor_kernel_boot

#write_boot; # use flash_boot to skip ramdisk repack, e.g. for dtb on devices with hdr v4 but no vendor_kernel_boot
## end vendor_boot install
