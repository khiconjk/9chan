### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=Samsung Galaxy S9 (SM-G960N) Stock Kernel
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=starlte
device.name2=starltexx
device.name3=starlteks
device.name4=SM-G960F
device.name5=SM-G960N
supported.versions=10-13
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
      sed -i 's/forceencrypt=footer/encryptable=footer/g' "$f";
      sed -i 's/fileencryption=[^,]*/encryptable/g' "$f";
    fi
  done
  for i in /vendor/etc/init/vk*.rc /vendor/etc/init/vaultkeeper* /vendor/etc/init/*wsm*; do
    if [ -f "$i" ]; then
      ui_print "  Disabling $i...";
      sed -i 's/^[^#].*$/# &/' "$i";
    fi
  done
  for mf in /vendor/etc/vintf/manifest.xml /vendor/etc/vintf/manifest/vaultkeeper_manifest.xml; do
    if [ -f "$mf" ]; then
      sed -i -e '/<hal format="hidl">/{N;/<name>vendor\.samsung.*\.security\.\(vaultkeeper\|wsm\)<\/name>/{:loop;N;/<\/hal>/!bloop;d}}' "$mf" 2>/dev/null;
    fi
  done
  if [ -f /vendor/bin/vaultkeeperd ]; then
    chmod 0 /vendor/bin/vaultkeeperd 2>/dev/null;
  fi
  ui_print "  Vendor patched successfully.";
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
