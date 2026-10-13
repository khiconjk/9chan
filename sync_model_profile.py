import os, subprocess

patches = {
    "build_prop": {
        "ro.product.model": "SM-G965F",
        "ro.product.device": "star2lte",
        "ro.product.name": "star2lte",
        "ro.build.product": "star2lte",
    },
    "build_vendor_prop": {
        "ro.product.vendor.model": "SM-G965F",
        "ro.product.vendor.device": "star2lte",
        "ro.product.vendor.name": "star2lte",
    },
    "build_odm_prop": {
        "ro.product.odm.model": "SM-G965F",
        "ro.product.odm.device": "star2lte",
        "ro.product.odm.name": "star2lte",
    },
    "bootloader_prop": {
        "ro.boot.em.model": "SM-G965F",
        "ro.bootloader": "G965FXXUHFVG5",
        "ro.boot.bootloader": "G965FXXUHFVG5",
    },
    "radio_prop": {
        "gsm.version.baseband": "G965FXXUHFVG5",
        "ril.sw_ver": "G965FXXUHFVG5",
        "ril.product_code": "SM-G965FZBDXXV",
    },
    "fingerprint_prop": {
        "ro.build.fingerprint": "samsung/star2lte/star2lte:13/TP1A.220624.014/G965FXXUHFVG5:user/release-keys",
    }
}

for ctx, prop_dict in patches.items():
    device_file = f"/dev/__properties__/u:object_r:{ctx}:s0"
    local_file = f"w:\\home\\khiconjk\\Samsung S9\\ss-S9\\{ctx}"
    
    # Check if exists on device
    chk = subprocess.run(["adb", "shell", f"ls {device_file}"], capture_output=True, text=True)
    if "No such file" in chk.stderr or "No such file" in chk.stdout:
        print(f"Skipping non-existent {ctx}")
        continue
        
    subprocess.run(["adb", "pull", device_file, local_file], check=True, capture_output=True)
    
    with open(local_file, "r+b") as f:
        data = f.read()
        for prop_name, new_val in prop_dict.items():
            prop_bytes = prop_name.encode()
            idx = data.find(prop_bytes)
            if idx != -1:
                start = idx - 96
                serial_word = int.from_bytes(data[start:start+4], "little")
                dirty = serial_word | 1
                f.seek(start)
                f.write(dirty.to_bytes(4, "little"))
                f.flush()
                
                new_val_bytes = new_val.encode() + b'\x00' * (92 - len(new_val))
                f.seek(start + 4)
                f.write(new_val_bytes)
                f.flush()
                
                clean = (len(new_val) << 24) | ((dirty + 1) & 0xFFFFFF)
                f.seek(start)
                f.write(clean.to_bytes(4, "little"))
                f.flush()
                print(f"[{ctx}] Patched {prop_name} -> {new_val}")
            else:
                print(f"[{ctx}] Property {prop_name} not found")
                
    # Push back and apply via dd
    tmp_path = f"/data/local/tmp/{ctx}"
    subprocess.run(["adb", "push", local_file, tmp_path], check=True, capture_output=True)
    cmd = f"chmod 644 {device_file}; dd if={tmp_path} of={device_file} conv=notrunc; chmod 444 {device_file}; rm -f {tmp_path}"
    subprocess.run(["adb", "shell", cmd], check=True, capture_output=True)

print("Done applying all patches!")
