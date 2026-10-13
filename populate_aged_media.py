import os
import subprocess
import datetime
from PIL import Image

TEMP_DIR = "temp_media"
os.makedirs(TEMP_DIR, exist_ok=True)

# 1. Camera Photos (Samsung Galaxy S9+ Camera)
camera_photos = [
    ("20260715_142010.jpg", "2026:07:15 14:20:10", (120, 150, 180)),
    ("20260728_183245.jpg", "2026:07:28 18:32:45", (200, 130, 90)),
    ("20260810_091530.jpg", "2026:08:10 09:15:30", (80, 160, 110)),
    ("20260822_204512.jpg", "2026:08:22 20:45:12", (45, 50, 75)),
    ("20260905_121008.jpg", "2026:09:05 12:10:08", (180, 180, 120)),
    ("20260918_173022.jpg", "2026:09:18 17:30:22", (190, 110, 130)),
    ("20260925_084519.jpg", "2026:09:25 08:45:19", (110, 140, 170)),
    ("20261002_191055.jpg", "2026:10:02 19:10:55", (70, 70, 90)),
    ("20261006_142540.jpg", "2026:10:06 14:25:40", (140, 160, 130)),
    ("20261009_115012.jpg", "2026:10:09 11:50:12", (160, 150, 140)),
]

subprocess.run(["adb", "shell", "mkdir -p /sdcard/DCIM/Camera /sdcard/Pictures/Screenshots /sdcard/Download"], check=True)

print("[1] Generating and pushing Camera Photos...")
for filename, dt_str, color in camera_photos:
    local_path = os.path.join(TEMP_DIR, filename)
    img = Image.new("RGB", (1920, 1080), color=color)
    
    # Standard EXIF tags for S9+
    exif = img.getexif()
    exif[0x010F] = "samsung"          # Make
    exif[0x0110] = "SM-G965F"         # Model
    exif[0x0131] = "G965FXXUHFVG5"    # Software
    exif[0x0132] = dt_str             # DateTime
    
    img.save(local_path, "jpeg", exif=exif)
    
    remote_path = f"/sdcard/DCIM/Camera/{filename}"
    subprocess.run(["adb", "push", local_path, remote_path], check=True, stdout=subprocess.DEVNULL)
    
    dt_obj = datetime.datetime.strptime(dt_str, "%Y:%m:%d %H:%M:%S")
    touch_str = dt_obj.strftime("%Y%m%d%H%M.%S")
    subprocess.run(["adb", "shell", f"touch -t {touch_str} {remote_path}"])
    subprocess.run(["adb", "shell", f"content call --uri content://media --method scan_file --arg {remote_path}"], stdout=subprocess.DEVNULL)

# 2. Screenshots (1080x2220 resolution)
screenshots = [
    ("Screenshot_20260812-101520_Shopee.jpg", "2026:08:12 10:15:20", (238, 77, 45)),
    ("Screenshot_20260825-143045_Chrome.jpg", "2026:08:25 14:30:45", (66, 133, 244)),
    ("Screenshot_20260915-210512_Facebook.jpg", "2026:09:15 21:05:12", (24, 119, 242)),
    ("Screenshot_20261003-094018_Maps.jpg", "2026:10:03 09:40:18", (52, 168, 83)),
]

print("[2] Generating and pushing Screenshots...")
for filename, dt_str, color in screenshots:
    local_path = os.path.join(TEMP_DIR, filename)
    img = Image.new("RGB", (1080, 2220), color=color)
    img.save(local_path, "jpeg")
    
    remote_path = f"/sdcard/Pictures/Screenshots/{filename}"
    subprocess.run(["adb", "push", local_path, remote_path], check=True, stdout=subprocess.DEVNULL)
    
    dt_obj = datetime.datetime.strptime(dt_str, "%Y:%m:%d %H:%M:%S")
    touch_str = dt_obj.strftime("%Y%m%d%H%M.%S")
    subprocess.run(["adb", "shell", f"touch -t {touch_str} {remote_path}"])
    subprocess.run(["adb", "shell", f"content call --uri content://media --method scan_file --arg {remote_path}"], stdout=subprocess.DEVNULL)

# 3. Download Documents (PDFs)
downloads = [
    ("Hoa_don_tien_dien_T08.pdf", "202608151030.00"),
    ("Bang_luong_thang_08_2026.pdf", "202609051410.00"),
    ("Hop_dong_thue_nha_ky_ket.pdf", "202607200900.00"),
    ("Thong_bao_thue_GTGT_2026.pdf", "202609201645.00"),
]

print("[3] Generating and pushing Download Documents...")
for filename, touch_str in downloads:
    local_path = os.path.join(TEMP_DIR, filename)
    with open(local_path, "wb") as f:
        f.write(b"%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n3 0 obj<</Type/Page/MediaBox[0 0 612 792]>>endobj\nxref\n0 4\n0000000000 65535 f\n0000000009 00000 n\n0000000052 00000 n\n0000000108 00000 n\ntrailer<</Size 4/Root 1 0 R>>\nstartxref\n165\n%%EOF\n")
    
    remote_path = f"/sdcard/Download/{filename}"
    subprocess.run(["adb", "push", local_path, remote_path], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["adb", "shell", f"touch -t {touch_str} {remote_path}"])
    subprocess.run(["adb", "shell", f"content call --uri content://media --method scan_file --arg {remote_path}"], stdout=subprocess.DEVNULL)

# Final volume scan
print("[4] Triggering full MediaProvider volume scan...")
subprocess.run(["adb", "shell", "content call --uri content://media --method scan_volume --arg external_primary"], check=True)

# Cleanup
for f in os.listdir(TEMP_DIR):
    os.remove(os.path.join(TEMP_DIR, f))
os.rmdir(TEMP_DIR)

print("Aged Media & Documents population complete!")
