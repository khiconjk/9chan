import os
import subprocess
import shutil

WORKSPACE = "/home/khiconjk/Samsung S9/ss-S9"
stock_rd = os.path.join(WORKSPACE, "stock_unpack", "ramdisk.cpio.gz")
stock_bak = os.path.join(WORKSPACE, "stock_unpack", "ramdisk.cpio.gz.bak")
adb_key = os.path.join(WORKSPACE, "adb_keys")
tmp_dir = "/tmp/rd_mod"

if not os.path.exists(stock_bak):
    shutil.copyfile(stock_rd, stock_bak)
    print(f"Backed up original ramdisk to {stock_bak}")

if os.path.exists(tmp_dir):
    shutil.rmtree(tmp_dir)
os.makedirs(tmp_dir, exist_ok=True)

# 1. Unpack stock ramdisk
subprocess.run(f"cd '{tmp_dir}' && gzip -dc '{stock_bak}' | cpio -idm", shell=True, check=True)

# 2. Add adb_keys (permissions 0644, user root:root)
dest_key = os.path.join(tmp_dir, "adb_keys")
shutil.copyfile(adb_key, dest_key)
os.chmod(dest_key, 0o644)
print(f"Added adb_keys: {os.path.getsize(dest_key)} bytes")

# 3. Repack ramdisk using standard newc format
out_rd = os.path.join(tmp_dir, "ramdisk_repacked.cpio.gz")
pack_cmd = f"cd '{tmp_dir}' && find . ! -name 'ramdisk_repacked.cpio.gz' | sort | cpio -o -H newc -R 0:0 | gzip -n -9 > '{out_rd}'"
subprocess.run(pack_cmd, shell=True, check=True)

# 4. Verify adb_keys in repacked ramdisk
verify_res = subprocess.run(f"gzip -dc '{out_rd}' | cpio -tv | grep adb_keys", shell=True, capture_output=True, text=True)
print("Verification in cpio:", verify_res.stdout.strip())

# 5. Overwrite stock_unpack/ramdisk.cpio.gz
shutil.copyfile(out_rd, stock_rd)
print(f"Updated {stock_rd}: {os.path.getsize(stock_rd)} bytes")
