# HƯỚNG DẪN TÍCH HỢP PCHANGER VỚI SAMSUNG S9 GHOST ENGINE
> **Tài liệu chuẩn dành cho Developer công cụ Phone Changer (PC-to-Android)**  
> **Áp dụng cho**: Samsung Galaxy S9 (`starlte` / `SM-G960N` / `SM-G960F`) chạy **Stock Android 10 One UI 2.5** với **Kernel Ghost VANILLA (Clean Non-Root)**.

---

## 1. NGUYÊN LÝ HOẠT ĐỘNG CỦA KERNEL GHOST ENGINE

1. **Điểm đích duy nhất của Kernel**:
   - Kernel Linux chỉ đọc duy nhất file cấu hình:  
     👉 **`/efs/ghost.conf`** (hoặc đường dẫn mount alias: `/mnt/vendor/efs/ghost.conf`).
2. **Cơ chế nạp tự động (Boot-time & Periodic Reload)**:
   - Khi thiết bị khởi động, Kernel sẽ nạp file này từ phân vùng EFS, bóc tách toàn bộ 58 trường danh tính và:
     - Ghi đè trực tiếp trong RAM thuộc tính hệ thống (`/dev/__properties__/`) qua cơ chế in-place versioned patching.
     - Ảo hóa tầng VFS (đọc xuyên không sửa đĩa) cho các file: `/efs/FactoryApp/serial_no`, `/efs/FactoryApp/imei`, `/efs/wifi/.mac.info`, `/efs/bluetooth/bt_addr`, v.v.
     - Cấp MAC phần cứng cho card mạng Broadcom Wi-Fi (`bcmdhd`).
     - Tự động duy trì Uptime ảo (~17 ngày).
3. **Ưu điểm lớn nhất của phân vùng `/efs`**:
   - Phân vùng `/efs` là phân vùng phần cứng độc lập (`/dev/block/bootdevice/by-name/efs`), **không bị mã hóa bởi FDE/FBE**.
   - Do đó, **kể cả khi bạn format sạch phân vùng `/data` (Factory Reset), file `/efs/ghost.conf` vẫn nguyên vẹn 100%**. Máy khởi động lên vẫn giữ danh tính mới được nạp.

---

## 2. BỐN (04) NGUYÊN NHÂN GÂY BOOTLOOP VÀ CÁCH PHÒNG TRÁNH TUYỆT ĐỐI

### ⚠️ Lỗi 1: Ký tự xuống dòng Windows (`CRLF` `\r\n`)
- **Hiện tượng**: Tool viết bằng C#, Python hoặc Batch trên Windows khi tạo hoặc đọc file thường giữ ký tự xuống dòng Windows `\r\n`. Khi Kernel C đọc, ký tự `\r` (0x0D) sẽ bị dính vào đuôi chuỗi (ví dụ: model thành `SM-G960N\r`, serial thành `fc91ed4fa4179a\r`). Điều này làm hỏng cấu trúc chuỗi của Android, gây crash service hoặc không nhận diện profile.
- **Giải pháp**: Tool luôn phải chuyển đổi `\r\n` thành `\n` (Unix LF) trước khi đẩy vào điện thoại.

### ⚠️ Lỗi 2: Ghi file nửa vời (Race Condition / Partial Write)
- **Hiện tượng**: Đẩy trực tiếp vào file đang sử dụng khi máy đang chạy hoặc mất kết nối giữa chừng khiến file chỉ có 0 byte hoặc đứt gãy nửa chừng. Kernel đọc trúng file rỗng sẽ không nạp được danh tính.
- **Giải pháp**: **Bắt buộc dùng cơ chế Atomic Push (Đẩy nguyên tử)**:
  1. Đẩy vào thư mục tạm: `/data/local/tmp/ghost.conf.tmp`.
  2. Kiểm tra kích thước file tạm trên máy (> 500 bytes).
  3. Dùng lệnh `cp -f` hoặc `mv` sang `/efs/ghost.conf`.
  4. Chạy lệnh `sync` để ghi đè dứt điểm xuống chip nhớ flash UFS.

### ⚠️ Lỗi 3: Sai phân vùng hoặc sai quyền truy cập (Permissions & SELinux)
- **Hiện tượng**: Đẩy nhầm vào `/system` (bị Read-Only) hoặc đẩy vào `/data` (bị mất khi format) hoặc file bị gán quyền `0000` khiến Kernel/System không đọc được.
- **Giải pháp**: 
  - Đích đến duy nhất: `/efs/ghost.conf`.
  - Phân quyền bắt buộc: `chmod 0644 /efs/ghost.conf`.
  - Chủ sở hữu: `chown system:radio /efs/ghost.conf` (hoặc `root:root`).

### ⚠️ Lỗi 4: Xóa dữ liệu sai cách làm hỏng khóa SSAID / SettingsProvider UserKey
- **CẢNH BÁO NGUY HIỂM NHẤT**:
  - Trên Android 10, **tuyệt đối KHÔNG ĐƯỢC tự tạo hoặc chép đè file `/data/system/users/0/settings_ssaid.xml`**.
  - File này được bảo vệ bởi khóa mật mã `userkey` nội bộ của `SettingsProvider`. Nếu tool tự ý chép file lạ vào, `SettingsProvider` sẽ ném ngoại lệ `IllegalStateException: User key invalid`, làm crash loop toàn bộ ứng dụng hệ thống Samsung (`com.samsung.android.mobileservice`, `com.samsung.android.app.reminder`), dẫn đến **treo máy không bao giờ vào được màn hình chính**.
- **Giải pháp đúng khi format/wipe**: Xem chi tiết ở Mục 4.

---

## 3. CẤU TRÚC CHUẨN CỦA 1 FILE PROFILE (`ghost.conf`)

Mỗi file trong kho profile trên PC phải là file văn bản thuần (UTF-8, LF), gồm 58 trường chuẩn như mẫu dưới đây:

```ini
# ========================================================
# S9 Ghost Profile Configuration (/efs/ghost.conf)
# 58 Fields Device Identity Profile
# ========================================================

# --- 1. BUILD FINGERPRINTS ---
ro.build.fingerprint=samsung/starlteks/starlteks:10/QP1A.190711.020/G960NKSU5FVG2:user/release-keys
ro.vendor.build.fingerprint=samsung/starlteks/starlteks:10/QP1A.190711.020/G960NKSU5FVG2:user/release-keys
ro.odm.build.fingerprint=samsung/starlteks/starlteks:10/QP1A.190711.020/G960NKSU5FVG2:user/release-keys
ro.bootimage.build.fingerprint=samsung/starlteks/starlteks:10/QP1A.190711.020/G960NKSU5FVG2:user/release-keys
ro.system_ext.build.fingerprint=samsung/starlteks/starlteks:10/QP1A.190711.020/G960NKSU5FVG2:user/release-keys

# --- 2. PRODUCT MODEL ---
ro.product.model=SM-G960N
ro.product.vendor.model=SM-G960N
ro.product.odm.model=SM-G960N
ro.product.system_ext.model=SM-G960N

# --- 3. PRODUCT BRAND ---
ro.product.brand=samsung
ro.product.vendor.brand=samsung
ro.product.odm.brand=samsung
ro.product.system_ext.brand=samsung

# --- 4. PRODUCT MANUFACTURER ---
ro.product.manufacturer=samsung
ro.product.vendor.manufacturer=samsung
ro.product.odm.manufacturer=samsung

# --- 5. PRODUCT NAME ---
ro.product.name=starlteks
ro.product.vendor.name=starlteks
ro.product.odm.name=starlteks
ro.product.system_ext.name=starlteks

# --- 6. PRODUCT DEVICE ---
ro.product.device=starlteks
ro.product.vendor.device=starlteks
ro.product.odm.device=starlteks
ro.product.system_ext.device=starlteks

# --- 7. BUILD METADATA ---
ro.build.id=QP1A.190711.020
ro.build.display.id=QP1A.190711.020.G960NKSU5FVG2
ro.build.version.incremental=G960NKSU5FVG2
ro.build.version.release=10
ro.build.version.sdk=29
ro.build.date=Wed Jul 20 15:30:00 KST 2022
ro.build.date.utc=1658302200
ro.build.type=user
ro.build.tags=release-keys
ro.build.description=starlteks-user 10 QP1A.190711.020 G960NKSU5FVG2 release-keys
ro.build.flavor=starlteks-user

# --- 8. SERIAL & HARDWARE IDENTIFIERS ---
ro.serialno=fc91ed4fa4179a
ro.boot.serialno=fc91ed4fa4179a
efs.serial_no=fc91ed4fa4179a
efs.ap_serial=0x0AB4CD813400
efs.em_did=200ab4cd81340011
efs.samsung_serial=R39K5076SW
efs.imei=352093091234567
efs.imsi=452041234567890

# --- 9. NETWORK MAC ADDRESSES ---
wifi_mac=00:1a:79:2b:4c:6d
bt_mac=00:1a:79:2b:4c:6e

# --- 10. TELEPHONY OPERATOR ---
gsm.sim.operator.alpha=Viettel
gsm.operator.alpha=Viettel
gsm.sim.operator.numeric=45204
gsm.operator.numeric=45204
gsm.sim.operator.iso-country=vn
gsm.operator.iso-country=vn

# --- 11. CSC & CARRIER ---
ro.csc.country_code=Vietnam
ro.csc.sales_code=XXV
ro.carrier=unknown

# --- 12. LOCALES & TIMEZONE ---
persist.sys.country=VN
persist.sys.language=vi
persist.sys.locale=vi-VN
persist.sys.timezone=Asia/Ho_Chi_Minh
```

---

## 4. QUY TRÌNH CHUẨN KHI PCHANGER THỰC HIỆN "CHANGE"

Tool Pchanger chạy trên PC cần tuân thủ đúng 5 bước sau:

```
[Kho Profile PC]
       │
       ▼ (1) Random chọn 1 profile
[Kiểm tra & Chuẩn hóa LF]
       │
       ▼ (2) ADB push an toàn vào file tạm
[/data/local/tmp/ghost.conf.tmp]
       │
       ▼ (3) Copy nguyên tử & phân quyền
[/efs/ghost.conf] (0644, system:radio)
       │
       ▼ (4) Xóa dữ liệu theo lựa chọn của Tool
  ┌────┴──────────────────────────┐
  ▼ (Lựa chọn A)                  ▼ (Lựa chọn B)
[Soft Clean - Từng App]       [Full Wipe Data An Toàn]
(pm clear + đổi Android ID)   (Xóa data có giữ bypass Setup)
       │                          │
       └────────────┬─────────────┘
                    ▼ (5)
             [adb reboot]
```

### Chi tiết các bước thực hiện:

#### Bước 1: Random chọn 1 profile từ thư mục trên PC
```python
import os, random

profile_dir = "C:\\pchanger\\profiles"
profiles = [f for f in os.listdir(profile_dir) if f.endswith(".conf")]
chosen_profile = os.path.join(profile_dir, random.choice(profiles))
```

#### Bước 2: Chuẩn hóa nội dung (Chống lỗi CRLF)
```python
with open(chosen_profile, "r", encoding="utf-8") as f:
    content = f.read()

# Bắt buộc chuẩn hóa xuống dòng về Unix LF
clean_content = content.replace("\r\n", "\n").replace("\r", "\n")

temp_local_file = "C:\\pchanger\\temp_profile.conf"
with open(temp_local_file, "w", encoding="utf-8", newline="\n") as f:
    f.write(clean_content)
```

#### Bước 3: Đẩy file an toàn lên thiết bị (Atomic Push)
Chạy lần lượt các lệnh ADB:
```bash
# 1. Đẩy vào thư mục tạm có quyền ghi
adb push "C:\pchanger\temp_profile.conf" /data/local/tmp/ghost.conf.tmp

# 2. Di chuyển đè nguyên tử vào /efs/ghost.conf và set quyền
adb shell "cp -f /data/local/tmp/ghost.conf.tmp /efs/ghost.conf && chmod 0644 /efs/ghost.conf && chown system:radio /efs/ghost.conf && sync"

# 3. Dọn dẹp file tạm
adb shell "rm -f /data/local/tmp/ghost.conf.tmp"
```

#### Bước 4: Xóa dữ liệu theo lựa chọn cấu hình của Tool

##### 👉 LỰA CHỌN A: Soft Clean (Khuyên dùng cho Phone Farm / Automation)
*Nhanh, không mất cài đặt hệ thống, không cần qua lại bootloader:*
```bash
# 1. Xóa dữ liệu ứng dụng mục tiêu (ví dụ app cần test)
adb shell pm clear com.target.app
adb shell pm clear com.google.android.gms

# 2. Reset Android ID (SSAID) ngẫu nhiên (16 ký tự hex)
# Lệnh này dùng API chuẩn của Settings, 100% không bao giờ gây lỗi SettingsProvider!
adb shell "settings put secure android_id $(openssl rand -hex 8)"
```

##### 👉 LỰA CHỌN B: Full Factory Reset (Xóa trắng phân vùng `/data`)
*Nếu tool của bạn muốn xóa sạch toàn bộ máy như xuất xưởng, bạn phải thực thi lệnh sau để KHÔNG BỊ KẸT SETUP WIZARD:*
```bash
# Đặt cờ bỏ qua Setup Wizard trước khi reboot
adb shell "settings put global device_provisioned 1"
adb shell "settings put secure user_setup_complete 1"
adb shell "settings put secure sec_setupwizard_complete 1"

# Thực hiện lệnh reset hệ thống chuẩn của Android
adb shell am broadcast -a android.intent.action.MASTER_CLEAR
```

#### Bước 5: Khởi động lại thiết bị
```bash
adb reboot
```
- Đợi thiết bị boot lại:
```bash
adb wait-for-device
```
- Khi máy boot lên: Kernel Ghost Engine sẽ tự động đọc `/efs/ghost.conf` mới, áp dụng đồng loạt 58 trường danh tính, tự động bypass Setup Wizard và vào thẳng màn hình chính!

---

## 5. CODE MẪU PYTHON HOÀN CHỈNH CHO PCHANGER

Bạn có thể tích hợp trực tiếp hàm Python dưới đây vào tool của mình:

```python
import os
import random
import subprocess
import time

class S9ProfileChanger:
    def __init__(self, profiles_dir):
        self.profiles_dir = profiles_dir

    def run_adb(self, cmd, timeout=15):
        try:
            full_cmd = f"adb {cmd}"
            res = subprocess.run(full_cmd, shell=True, capture_output=True, text=True, timeout=timeout)
            return res.returncode == 0, res.stdout.strip(), res.stderr.strip()
        except Exception as e:
            return False, "", str(e)

    def change_profile(self, wipe_mode="soft", target_package=None):
        """
        wipe_mode: 'none', 'soft' (pm clear + new android_id), hoặc 'full' (factory reset)
        """
        # 1. Kiểm tra kết nối thiết bị
        ok, out, _ = self.run_adb("devices")
        if "device\n" not in out and not out.endswith("device"):
            print("[-] Lỗi: Không tìm thấy thiết bị ADB đã kết nối hoặc chưa cấp quyền!")
            return False

        # 2. Chọn ngẫu nhiên 1 profile .conf
        candidates = [f for f in os.listdir(self.profiles_dir) if f.endswith(".conf")]
        if not candidates:
            print("[-] Lỗi: Thư mục profiles không có file .conf nào!")
            return False

        selected = os.path.join(self.profiles_dir, random.choice(candidates))
        print(f"[+] Đang chọn profile ngẫu nhiên: {os.path.basename(selected)}")

        # 3. Đọc và chuẩn hóa LF (loại bỏ CRLF của Windows)
        with open(selected, "r", encoding="utf-8") as f:
            raw_text = f.read()
        clean_text = raw_text.replace("\r\n", "\n").replace("\r", "\n")

        temp_path = os.path.join(self.profiles_dir, "_temp_send.conf")
        with open(temp_path, "w", encoding="utf-8", newline="\n") as f:
            f.write(clean_text)

        # 4. Đẩy file an toàn (Atomic Push)
        print("[+] Đang đẩy file cấu hình vào /efs/ghost.conf...")
        ok, _, err = self.run_adb(f'push "{temp_path}" /data/local/tmp/ghost.conf.tmp')
        if not ok:
            print(f"[-] Lỗi push file tạm: {err}")
            return False

        # Copy đè sang /efs, phân quyền 0644 và sync
        deploy_cmd = 'shell "cp -f /data/local/tmp/ghost.conf.tmp /efs/ghost.conf && chmod 0644 /efs/ghost.conf && chown system:radio /efs/ghost.conf && sync"'
        ok, _, err = self.run_adb(deploy_cmd)
        self.run_adb('shell "rm -f /data/local/tmp/ghost.conf.tmp"')
        if os.path.exists(temp_path):
            os.remove(temp_path)

        if not ok:
            print(f"[-] Lỗi triển khai vào /efs: {err}")
            return False

        # 5. Xử lý xóa dữ liệu theo chế độ
        if wipe_mode == "soft":
            print("[+] Đang thực hiện Soft Clean (Reset Android ID & Data App)...")
            # Sinh Android ID ngẫu nhiên 16 ký tự hex
            new_android_id = "".join([random.choice("0123456789abcdef") for _ in range(16)])
            self.run_adb(f'shell "settings put secure android_id {new_android_id}"')
            if target_package:
                self.run_adb(f'shell "pm clear {target_package}"')
            self.run_adb('shell "pm clear com.google.android.gms"')

        elif wipe_mode == "full":
            print("[+] Đang chuẩn bị Full Reset (Bypass Setup Wizard)...")
            self.run_adb('shell "settings put global device_provisioned 1"')
            self.run_adb('shell "settings put secure user_setup_complete 1"')
            self.run_adb('shell "settings put secure sec_setupwizard_complete 1"')
            self.run_adb('shell "am broadcast -a android.intent.action.MASTER_CLEAR"')
            return True

        # 6. Khởi động lại thiết bị
        print("[+] Khởi động lại thiết bị để nạp danh tính mới...")
        self.run_adb("reboot")
        return True

# --- Ví dụ sử dụng ---
if __name__ == "__main__":
    changer = S9ProfileChanger(profiles_dir="C:\\pchanger\\profiles")
    # Đổi profile và xóa sạch dữ liệu ứng dụng chỉ định:
    changer.change_profile(wipe_mode="soft", target_package="com.shopee.vn")
```

---

## 6. BẢNG CHECKLIST AN TOÀN TRƯỚC KHI CHẠY TOOL

| Tiêu chí kiểm tra | Đạt chuẩn | Cảnh báo nguy cơ |
| :--- | :---: | :--- |
| **Đường dẫn đích** | `/efs/ghost.conf` | Tuyệt đối không trỏ vào `/system`, `/data/system/`, `/vendor` |
| **Định dạng file** | Unix `LF` (`\n`) | Không để dính `\r\n` của Windows Text Editor |
| **Quyền file trên máy** | `0644` (`-rw-r--r--`) | Không để `0000` hoặc thiếu quyền đọc |
| **Quy trình đẩy file** | Đẩy qua `/data/local/tmp` rồi `cp` | Không ghi trực tiếp làm hỏng file khi truyền nửa chừng |
| **Xóa Android ID** | Dùng `settings put secure android_id` | **KHÔNG** can thiệp trực tiếp file `settings_ssaid.xml` |
| **Bypass Setup Wizard** | Kernel tự động nạp `FINISH` | Không lo bị kẹt màn hình khởi tạo khi wipe |
