import zipfile
import os

jar_in = "services.jar"
jar_out = "services_patched.jar"
dex_patch = "classes_patched.dex"

print(f"Reading {jar_in}...")
with zipfile.ZipFile(jar_out, 'w', compression=zipfile.ZIP_DEFLATED) as zout:
    with zipfile.ZipFile(jar_in, 'r') as zin:
        for item in zin.infolist():
            if item.filename == 'classes.dex':
                print(f"Replacing {item.filename} with {dex_patch}...")
                with open(dex_patch, 'rb') as f:
                    zout.writestr(item, f.read())
            else:
                zout.writestr(item, zin.read(item.filename))

print(f"Done! {jar_out} created. Size: {os.path.getsize(jar_out)} bytes")
