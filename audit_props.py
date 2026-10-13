import subprocess

files = [
    '/system/system_ext/etc/build.prop',
    '/system/build.prop',
    '/system/system_dlkm/etc/build.prop',
    '/system/product/etc/build.prop',
    '/vendor/build.prop',
    '/vendor/odm/etc/build.prop',
    '/vendor/odm_dlkm/etc/build.prop',
    '/vendor/vendor_dlkm/etc/build.prop'
]
for f in files:
    cmd = f'grep -E "ro\\.product\\..*\\.(name|model|device)" {f} 2>/dev/null'
    proc = subprocess.run(['adb', 'shell', cmd], capture_output=True, text=True)
    print(f'=== {f} ===')
    print(proc.stdout.strip())
