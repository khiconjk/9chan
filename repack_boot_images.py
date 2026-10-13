import struct
import hashlib
import os
import tarfile

import sys

if sys.platform.startswith("linux"):
    WORKSPACE = "/home/khiconjk/Samsung S9/ss-S9"
else:
    WORKSPACE = r"w:\home\khiconjk\Samsung S9\ss-S9"
RAMDISK_PATH = os.path.join(WORKSPACE, "stock_unpack", "ramdisk.cpio.gz")
PARTITION_SIZE = 57671680
PAGE_SIZE = 2048
KERNEL_ADDR = 0x10008000
RAMDISK_ADDR = 0x11000000
TAGS_ADDR = 0x10000100
OS_VERSION = 0x1a00017b
CMDLINE = b"buildvariant=userdebug"

def pack_boot(kernel_path, dtb_path, ramdisk_path, out_img_path, out_tar_path=None):
    with open(kernel_path, "rb") as f:
        k_data = f.read()
    with open(ramdisk_path, "rb") as f:
        r_data = f.read()
    with open(dtb_path, "rb") as f:
        e_data = f.read()

    k_sz = len(k_data)
    r_sz = len(r_data)
    e_sz = len(e_data)

    k_pages = (k_sz + PAGE_SIZE - 1) // PAGE_SIZE
    r_pages = (r_sz + PAGE_SIZE - 1) // PAGE_SIZE
    e_pages = (e_sz + PAGE_SIZE - 1) // PAGE_SIZE

    # Compute SHA1
    h = hashlib.sha1()
    h.update(k_data)
    h.update(struct.pack("<I", k_sz))
    h.update(r_data)
    h.update(struct.pack("<I", r_sz))
    h.update(b"")
    h.update(struct.pack("<I", 0))
    h.update(e_data)
    h.update(struct.pack("<I", e_sz))
    sha = h.digest() + b"\x00" * 12

    hdr = bytearray(PAGE_SIZE)
    hdr[0:8] = b"ANDROID!"
    struct.pack_into("<10I", hdr, 8,
        k_sz, KERNEL_ADDR,
        r_sz, RAMDISK_ADDR,
        0, 0x0,
        TAGS_ADDR,
        PAGE_SIZE,
        e_sz,
        OS_VERSION
    )
    hdr[64:64+len(CMDLINE)] = CMDLINE
    hdr[576:608] = sha

    packed = bytearray()
    packed.extend(hdr)
    packed.extend(k_data)
    packed.extend(b"\x00" * (k_pages * PAGE_SIZE - k_sz))
    packed.extend(r_data)
    packed.extend(b"\x00" * (r_pages * PAGE_SIZE - r_sz))
    packed.extend(e_data)
    packed.extend(b"\x00" * (e_pages * PAGE_SIZE - e_sz))

    # Add Samsung footer
    packed.extend(b"SEANDROIDENFORCE\x00\x00\x00\x00")

    # Pad to partition size if smaller
    if len(packed) < PARTITION_SIZE:
        packed.extend(b"\x00" * (PARTITION_SIZE - len(packed)))
    else:
        raise ValueError(f"Packed image size {len(packed)} exceeds partition size {PARTITION_SIZE}")

    with open(out_img_path, "wb") as f:
        f.write(packed)

    print(f"Created {out_img_path}: {len(packed)} bytes (k_sz={k_sz}, r_sz={r_sz}, e_sz={e_sz})")

    if out_tar_path:
        # Create uncompressed tar containing boot.img
        # For Odin, file inside tar should be named "boot.img"
        temp_boot = os.path.join(WORKSPACE, "boot.img")
        with open(temp_boot, "wb") as f:
            f.write(packed)
        with tarfile.open(out_tar_path, "w") as tar:
            tar.add(temp_boot, arcname="boot.img")
        if os.path.exists(temp_boot):
            os.remove(temp_boot)
        print(f"Created Odin tar: {out_tar_path} ({os.path.getsize(out_tar_path)} bytes)")

if __name__ == "__main__":
    # 1. KSUN + SUSFS
    ksu_kernel = os.path.join(WORKSPACE, "Image_ksu_susfs")
    if os.path.exists(ksu_kernel):
        pack_boot(
            kernel_path=ksu_kernel,
            dtb_path=os.path.join(WORKSPACE, "dtb_ksu_susfs.img"),
            ramdisk_path=RAMDISK_PATH,
            out_img_path=os.path.join(WORKSPACE, "boot_pixel13_ksu_susfs_fixed.img"),
            out_tar_path=os.path.join(WORKSPACE, "boot_pixel13_ksu_susfs_fixed.tar")
        )

    # 2. VANILLA
    vanilla_kernel = os.path.join(WORKSPACE, "Image_vanilla")
    if os.path.exists(vanilla_kernel):
        pack_boot(
            kernel_path=vanilla_kernel,
            dtb_path=os.path.join(WORKSPACE, "dtb_vanilla.img"),
            ramdisk_path=RAMDISK_PATH,
            out_img_path=os.path.join(WORKSPACE, "boot_pixel13_vanilla_fixed.img"),
            out_tar_path=os.path.join(WORKSPACE, "boot_pixel13_vanilla_fixed.tar")
        )
