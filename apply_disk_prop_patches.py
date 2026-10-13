import subprocess

commands = [
    # 1. Patch /vendor/odm_dlkm/etc/build.prop
    '''cat << 'EOF' > /vendor/odm_dlkm/etc/build.prop
####################################
# from generate-common-build-props
# These properties identify this partition image.
####################################
ro.product.odm_dlkm.brand=samsung
ro.product.odm_dlkm.device=g0s
ro.product.odm_dlkm.manufacturer=samsung
ro.product.odm_dlkm.model=SM-S906B
ro.product.odm_dlkm.name=g0sxxx
ro.odm_dlkm.build.date=Sat Dec 16 14:17:52 UTC 2023
ro.odm_dlkm.build.date.utc=1702736272
ro.odm_dlkm.build.fingerprint=samsung/g0sxxx/g0s:13/TQ3A.230901.001.B1/1702736338:user/release-keys
ro.odm_dlkm.build.id=TQ3A.230901.001.B1
ro.odm_dlkm.build.tags=release-keys
ro.odm_dlkm.build.type=user
ro.odm_dlkm.build.version.incremental=1702736338
ro.odm_dlkm.build.version.release=13
ro.odm_dlkm.build.version.release_or_codename=13
ro.odm_dlkm.build.version.sdk=33
EOF
chmod 644 /vendor/odm_dlkm/etc/build.prop
chown 0:0 /vendor/odm_dlkm/etc/build.prop
''',

    # 2. Patch /system/system_dlkm/etc/build.prop
    '''cat << 'EOF' > /system/system_dlkm/etc/build.prop
####################################
# from generate-common-build-props
# These properties identify this partition image.
####################################
ro.product.system_dlkm.brand=samsung
ro.product.system_dlkm.device=g0s
ro.product.system_dlkm.manufacturer=samsung
ro.product.system_dlkm.model=SM-S906B
ro.product.system_dlkm.name=g0sxxx
ro.system_dlkm.build.date=Tue Jul 12 18:30:00 KST 2022
ro.system_dlkm.build.date.utc=1657618200
ro.system_dlkm.build.fingerprint=samsung/g0sxxx/g0s:13/TQ3A.230901.001.B1/1702736338:user/release-keys
ro.system_dlkm.build.id=TQ3A.230705.001
ro.system_dlkm.build.tags=release-keys
ro.system_dlkm.build.type=user
ro.system_dlkm.build.version.incremental=1702736338
ro.system_dlkm.build.version.release=13
ro.system_dlkm.build.version.release_or_codename=13
ro.system_dlkm.build.version.sdk=33
EOF
chmod 644 /system/system_dlkm/etc/build.prop
chown 0:0 /system/system_dlkm/etc/build.prop
''',

    # 3. Patch /system/system_ext/etc/build.prop
    '''cat << 'EOF' > /system/system_ext/etc/build.prop
####################################
# from generate-common-build-props
# These properties identify this partition image.
####################################
ro.product.system_ext.brand=samsung
ro.product.system_ext.device=g0s
ro.product.system_ext.manufacturer=samsung
ro.product.system_ext.model=SM-S906B
ro.product.system_ext.name=g0sxxx
ro.system_ext.build.date=Tue Jan 06 12:09:31 ICT 2026
ro.system_ext.build.date.utc=1761023371
ro.system_ext.build.fingerprint=samsung/g0sxxx/g0s:13/TQ3A.230901.001.B1/1702736338:user/release-keys
ro.system_ext.build.id=TQ3A.230901.001.B1
ro.system_ext.build.tags=release-keys
ro.system_ext.build.type=user
ro.system_ext.build.version.incremental=1702736338
ro.system_ext.build.version.release=13
ro.system_ext.build.version.release_or_codename=13
ro.system_ext.build.version.sdk=33
####################################
# from variable PRODUCT_SYSTEM_EXT_PROPERTIES
####################################
EOF
chmod 644 /system/system_ext/etc/build.prop
chown 0:0 /system/system_ext/etc/build.prop
''',

    # 4. Ensure ro.product.* are explicitly in /system/build.prop
    '''
grep -q '^ro.product.model=' /system/build.prop || sed -i '/ro.product.system.model=/a ro.product.model=SM-S906B' /system/build.prop
grep -q '^ro.product.name=' /system/build.prop || sed -i '/ro.product.system.name=/a ro.product.name=g0sxxx' /system/build.prop
grep -q '^ro.product.device=' /system/build.prop || sed -i '/ro.product.system.device=/a ro.product.device=g0s' /system/build.prop
grep -q '^ro.product.brand=' /system/build.prop || sed -i '/ro.product.system.brand=/a ro.product.brand=samsung' /system/build.prop
grep -q '^ro.product.manufacturer=' /system/build.prop || sed -i '/ro.product.system.manufacturer=/a ro.product.manufacturer=samsung' /system/build.prop
''',

    # 5. Ensure ro.product.* are explicitly in /vendor/build.prop
    '''
grep -q '^ro.product.model=' /vendor/build.prop || sed -i '/ro.product.vendor.model=/a ro.product.model=SM-S906B' /vendor/build.prop
grep -q '^ro.product.name=' /vendor/build.prop || sed -i '/ro.product.vendor.name=/a ro.product.name=g0sxxx' /vendor/build.prop
grep -q '^ro.product.device=' /vendor/build.prop || sed -i '/ro.product.vendor.device=/a ro.product.device=g0s' /vendor/build.prop
grep -q '^ro.product.brand=' /vendor/build.prop || sed -i '/ro.product.vendor.brand=/a ro.product.brand=samsung' /vendor/build.prop
grep -q '^ro.product.manufacturer=' /vendor/build.prop || sed -i '/ro.product.vendor.manufacturer=/a ro.product.manufacturer=samsung' /vendor/build.prop
'''
]

for idx, c in enumerate(commands, 1):
    print(f"Applying patch {idx}...")
    p = subprocess.run(['adb', 'shell', c], capture_output=True, text=True)
    if p.returncode != 0:
        print(f"Error in patch {idx}: {p.stderr}")
    else:
        print(f"Patch {idx} OK")

print("All disk build.prop patches applied!")
