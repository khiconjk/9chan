# TÀI LIỆU TOÀN TẬP TẤT CẢ CÁC BẢN VÁ (PATCHES) ĐÃ THỰC HIỆN TRÊN SAMSUNG GALAXY S9 (G960N / STARLTE)

> **Mục đích:** Tài liệu này tổng hợp 100% tất cả các bản vá mã nguồn Kernel, Rom hệ thống Android 10, công cụ Pchanger 4.4, cơ chế Stealth Headless Always-On ADB và Fast First-Boot Engine đã được triển khai, kiểm thử và xác nhận hoạt động ổn định trên thiết bị Samsung Galaxy S9 (Exynos 9810).
> **Ngày lập:** 23/09/2026.

---

## MỤC LỤC
1. [Phần 1: Các bản vá tầng Kernel Linux (S9 Ghost Kernel)](#phần-1-các-bản-vá-tầng-kernel-linux-s9-ghost-kernel)
   - 1.1. VFS File Redirection & Chặn mở file ẩn (`fs/namei.c`)
   - 1.2. Ẩn tệp tin khỏi lệnh duyệt thư mục `readdir` / `getdents64` (`fs/readdir.c`)
   - 1.3. Khóa cứng dấu thời gian Factory ROM `stat` / `mtime` (`fs/stat.c`)
   - 1.4. Vá bộ nhớ thuộc tính hệ thống Android `/dev/__properties__/` (`kernel/s9_ghost_serial.c`)
   - 1.5. Cấu hình AnyKernel3 và kịch bản biên dịch siêu tốc (`fast_build.sh`)
2. [Phần 2: Cơ chế Stealth Headless Always-On ADB (Không Cần Màn Hình)](#phần-2-cơ-chế-stealth-headless-always-on-adb-không-cần-màn-hình)
   - 2.1. Vá nhị phân `/system/bin/adbd` và `/system/lib64/libadbd.so` (Bypass RSA In-Memory)
   - 2.2. Khóa xác thực phần cứng `/system/etc/adb_keys`
   - 2.3. Dịch vụ Watchdog ADB `/system/etc/init/init.fix_storage.rc`
3. [Phần 3: Bộ tăng tốc khởi động sau khi Format Data (Fast First-Boot Engine)](#phần-3-bộ-tăng-tốc-khởi-động-sau-khi-format-data-fast-first-boot-engine)
   - 3.1. Danh sách 103 gói rác Samsung & Nhà mạng Hàn Quốc đã Debloat
   - 3.2. Bộ đệm Dalvik-Cache không nén `/system/etc/fastboot_dalvik.tar`
   - 3.3. Tối ưu hóa Build Properties `/system/build.prop`
   - 3.4. Script kích hoạt boot siêu tốc `/system/etc/init/fastboot_seed.sh`
4. [Phần 4: Đồng bộ công cụ Pchanger 4.4 (`D:\ROM\pchanger`)](#phần-4-đồng-bộ-công-cụ-pchanger-44-drompchanger)
   - 4.1. Sửa lỗi tọa độ GPS thực tế Việt Nam (`RecoveryHelper.java`)
   - 4.2. Khởi tạo cấu trúc Direct Boot DE/CE chống Bootloop sau Wipe
   - 4.3. Bung tự động `fastboot_dalvik.tar` và gán cờ `adb_enabled=0`
   - 4.4. Nút bấm "Disable Apps (ADB)" trên giao diện Pchanger
5. [Phần 5: Chẩn đoán & Khắc phục triệt để lỗi Bootloop & Crash Modal (SQLite 1294 & 1806)](#phần-5-chẩn-đoán--khắc-phục-triệt-để-lỗi-bootloop--crash-modal-sqlite-1294--1806)
   - 5.1. Cơ chế lỗi gốc rễ (Root Causes)
   - 5.2. Các giải pháp đã triển khai triệt để & Tệp vá liên quan
   - 5.3. Cơ chế Root Execution Bridge & Kịch bản phục hồi tự động 321 gói ứng dụng
   - 5.4. Kết quả kiểm chứng thực nghiệm
6. [Phần 6: Bước thực hiện / Tái tạo từ đầu (Reproduction Steps)](#phần-6-bước-thực-hiện--tái-tạo-từ-đầu-reproduction-steps)
7. [Phần 7: Khắc phục triệt để lỗi mất 3 phím điều hướng & Chống lệch thuộc tính RIL/ODM (Anti-RILD Overwrite & Build.prop Placeholders)](#phần-7-khắc-phục-triệt-để-lỗi-mất-3-phím-điều-hướng--chống-lệch-thuộc-tính-rilodm-anti-rild-overwrite--buildprop-placeholders)
   - 7.1. Hiện tượng & Phân tích nguyên nhân gốc rễ (Root Causes)
   - 7.2. Các giải pháp kỹ thuật đã triển khai & Danh sách tệp vá
   - 7.3. Kết quả kiểm chứng thực nghiệm & Bảng đối chiếu thuộc tính

---

## PHẦN 1: CÁC BẢN VÁ TẦNG KERNEL LINUX (S9 GHOST KERNEL)
**Thư mục mã nguồn:** `w:\home\khiconjk\s9-ksu-susfs-build`

### 1.1. VFS File Redirection & Chặn mở file ẩn (`fs/namei.c`)
* **Mục đích:**
  - Chặn các ứng dụng thông thường (`UID >= 10000`) gọi `open()`, `stat()`, `access()` vào các tệp/thư mục tùy biến (`s9_serial`, `s9_gps`, `fastboot_dalvik.tar`, `fastboot_seed.sh`, `init.fix_storage.rc`, `adb_keys`, `adbd.orig`, `libadbd.so.orig`, `ghost.conf`, `/data/adb`), trả về ngay `-ENOENT` (`No such file or directory`).
  - Chuyển hướng trong suốt (`transparent redirection`): Khi ứng dụng cố đọc `/system/bin/adbd` hoặc `/system/lib64/libadbd.so` để kiểm tra mã SHA-256/CRC32, Kernel tự động chuyển hướng sang đọc tệp gốc Samsung nguyên bản (`adbd.orig` / `libadbd.so.orig`).

```diff
--- a/fs/namei.c
+++ b/fs/namei.c
@@ -1872,9 +1872,31 @@ static inline int should_follow_link(struct nameidata *nd, struct path *link,
 
 enum {WALK_GET = 1, WALK_PUT = 2};
 
+static inline bool s9_is_ghost_hidden_filename(const char *name, int len)
+{
+	if (!name || len <= 0)
+		return false;
+	if ((len == 9 && memcmp(name, "s9_serial", 9) == 0) ||
+	    (len == 6 && memcmp(name, "s9_gps", 6) == 0) ||
+	    (len == 11 && memcmp(name, "s9_headless", 11) == 0) ||
+	    (len == 19 && memcmp(name, "fastboot_dalvik.tar", 19) == 0) ||
+	    (len == 22 && memcmp(name, "fastboot_dalvik.tar.gz", 22) == 0) ||
+	    (len == 16 && memcmp(name, "fastboot_seed.sh", 16) == 0) ||
+	    (len == 19 && memcmp(name, "init.fix_storage.rc", 19) == 0) ||
+	    (len == 8 && memcmp(name, "adb_keys", 8) == 0) ||
+	    (len == 9 && memcmp(name, "adbd.orig", 9) == 0) ||
+	    (len == 15 && memcmp(name, "libadbd.so.orig", 15) == 0) ||
+	    (len == 10 && memcmp(name, "ghost.conf", 10) == 0) ||
+	    (len >= 9 && memcmp(name, "ghost_loc", 9) == 0))
+		return true;
+	return false;
+}
+
 static inline bool s9_is_hidden_adb_dentry(struct dentry *dentry)
 {
 	struct dentry *cur = dentry;
+	if (cur && s9_is_ghost_hidden_filename(cur->d_name.name, cur->d_name.len))
+		return true;
 	while (cur && cur->d_parent && cur != cur->d_parent) {
 		struct dentry *p = cur->d_parent;
 		if (cur->d_name.len == 3 && memcmp(cur->d_name.name, "adb", 3) == 0) {
@@ -1890,7 +1912,9 @@ static inline bool s9_is_hidden_adb_dentry(struct dentry *dentry)
 
 static inline bool s9_is_blocked_adb_component(struct nameidata *nd)
 {
-	if (unlikely(current_uid().val >= 10000)) {
+	if (unlikely(current_uid().val >= 10000) && (!nd->name || nd->name->uptr != NULL)) {
+		if (s9_is_ghost_hidden_filename(nd->last.name, nd->last.len))
+			return true;
 		if (nd->last.len == 3 && memcmp(nd->last.name, "adb", 3) == 0) {
 			struct dentry *p = nd->path.dentry;
 			if (p) {
@@ -3367,7 +3391,7 @@ static int lookup_open(struct nameidata *nd, struct path *path,
 		}
 #endif
 		/* S9 Ghost: Block cached /data/adb dentry for untrusted apps */
-		if (unlikely(current_uid().val >= 10000 && s9_is_hidden_adb_dentry(dentry))) {
+		if (unlikely(current_uid().val >= 10000 && (!nd->name || nd->name->uptr != NULL) && s9_is_hidden_adb_dentry(dentry))) {
 			dput(dentry);
 			return -ENOENT;
 		}
@@ -3808,14 +3832,26 @@ struct file *do_filp_open(int dfd, struct filename *pathname,
 	struct nameidata nd;
 	int flags = op->lookup_flags;
 	struct file *filp;
+	struct filename *redir_name = NULL;
+
+	if (unlikely(current_uid().val >= 10000 && pathname && pathname->name)) {
+		if (!strcmp(pathname->name, "/system/lib64/libadbd.so"))
+			redir_name = getname_kernel("/system/lib64/libadbd.so.orig");
+		else if (!strcmp(pathname->name, "/system/bin/adbd"))
+			redir_name = getname_kernel("/system/bin/adbd.orig");
+		if (IS_ERR(redir_name))
+			redir_name = NULL;
+	}
 
-	set_nameidata(&nd, dfd, pathname);
+	set_nameidata(&nd, dfd, redir_name ? redir_name : pathname);
 	filp = path_openat(&nd, op, flags | LOOKUP_RCU);
 	if (unlikely(filp == ERR_PTR(-ECHILD)))
 		filp = path_openat(&nd, op, flags);
 	if (unlikely(filp == ERR_PTR(-ESTALE)))
 		filp = path_openat(&nd, op, flags | LOOKUP_REVAL);
 	restore_nameidata();
+	if (unlikely(redir_name))
+		putname(redir_name);
 	return filp;
 }
```

---

### 1.2. Ẩn tệp tin khỏi lệnh duyệt thư mục `readdir` / `getdents64` (`fs/readdir.c`)
* **Mục đích:** Khi bất kỳ ứng dụng nào dùng `File.listFiles()`, `opendir()`, `readdir()`, hoặc các hàm native gọi `getdents64` để quét `/system/etc`, `/system/etc/init`, `/system/bin`, `/system/lib64`, `/proc`, các tệp tùy biến sẽ bị loại bỏ hoàn toàn khỏi mảng kết quả.

```diff
--- a/fs/readdir.c
+++ b/fs/readdir.c
@@ -169,14 +169,35 @@ struct getdents_callback {
 
 static inline bool s9_ghost_should_hide_dirent(struct file *file, const char *name, int namlen)
 {
+	uid_t uid;
 	if (unlikely(!name || namlen <= 0))
 		return false;
 
-	if (unlikely(current_uid().val >= 10000)) {
+	uid = current_uid().val;
+
+	/* Hide ghost proc entries from all users except root (0) and shell (2000) */
+	if (unlikely(uid != 0 && uid != 2000)) {
 		if (namlen == 9 && memcmp(name, "s9_serial", 9) == 0)
 			return true;
 		if (namlen == 6 && memcmp(name, "s9_gps", 6) == 0)
 			return true;
+		if (namlen == 11 && memcmp(name, "s9_headless", 11) == 0)
+			return true;
+	}
+
+	/* Hide custom system/data/efs artifacts from untrusted apps (UID >= 10000) */
+	if (unlikely(uid >= 10000)) {
+		if ((namlen == 19 && memcmp(name, "fastboot_dalvik.tar", 19) == 0) ||
+		    (namlen == 22 && memcmp(name, "fastboot_dalvik.tar.gz", 22) == 0) ||
+		    (namlen == 16 && memcmp(name, "fastboot_seed.sh", 16) == 0) ||
+		    (namlen == 19 && memcmp(name, "init.fix_storage.rc", 19) == 0) ||
+		    (namlen == 8 && memcmp(name, "adb_keys", 8) == 0) ||
+		    (namlen == 9 && memcmp(name, "adbd.orig", 9) == 0) ||
+		    (namlen == 15 && memcmp(name, "libadbd.so.orig", 15) == 0) ||
+		    (namlen == 10 && memcmp(name, "ghost.conf", 10) == 0) ||
+		    (namlen >= 9 && memcmp(name, "ghost_loc", 9) == 0))
+			return true;
+
 		if (namlen == 3 && memcmp(name, "adb", 3) == 0) {
 			if (file && file->f_path.dentry) {
 				struct dentry *d = file->f_path.dentry;
```

---

### 1.3. Khóa cứng dấu thời gian Factory ROM `stat` / `mtime` (`fs/stat.c`)
* **Mục đích:** Ngăn chặn ứng dụng phát hiện phân vùng `/system` bị chỉnh sửa thông qua thời gian sửa đổi gần nhất (`mtime`/`ctime`/`atime`). Ép cứng thời gian của các tệp và thư mục hệ thống về mốc `1230768000` (`01/01/2009 07:00:00 UTC+7`).

```diff
--- a/fs/stat.c
+++ b/fs/stat.c
@@ -135,6 +135,20 @@ static void s9_ghost_harmonize_stat(struct path *path, struct kstat *stat)
 			match = true;
 	}
 
+	if (strcmp(dname, "adbd") == 0 || strcmp(dname, "libadbd.so") == 0 ||
+	    strcmp(dname, "build.prop") == 0 || strcmp(dname, "etc") == 0 ||
+	    strcmp(dname, "init") == 0 || strcmp(dname, "app") == 0 ||
+	    strcmp(dname, "priv-app") == 0) {
+		if (stat->mtime.tv_sec > 1300000000) {
+			stat->mtime.tv_sec = 1230768000;
+			stat->mtime.tv_nsec = 0;
+			stat->ctime.tv_sec = 1230768000;
+			stat->ctime.tv_nsec = 0;
+			stat->atime.tv_sec = 1230768000;
+			stat->atime.tv_nsec = 0;
+		}
+	}
+
 	if (match) {
 		struct timespec64 bt;
 		u64 ghost_bt;
```

---

### 1.4. Vá bộ nhớ thuộc tính hệ thống Android `/dev/__properties__/` (`kernel/s9_ghost_serial.c`)
* **Mục đích:**
  - Vá trực tiếp vào 31 ngữ cảnh SELinux của bộ nhớ `/dev/__properties__/`:
    - `sys.usb.config` = `mtp`
    - `sys.usb.state` = `mtp`
    - `persist.sys.usb.config` = `mtp`
    - `init.svc.adbd` = `stopped`
    - Xóa trắng các cờ tùy biến: `debug.sf.nobootanimation`, `persist.sys.zygote.early`, `ro.pchanger.android`, `ro.pchanger.Active`.
  - **Khắc phục lỗi đè hậu tố tên thuộc tính (Suffix Overlap Bug):** Khi duyệt mảng `prop_info` trong file ngữ cảnh, bắt buộc kiểm tra `buf[i + 95] == '\0'` (byte kết thúc của mảng `value[92]`) và nhảy qua độ dài của `name` (`i += (96 + name_len) & ~3`), tránh trường hợp chuỗi `persist.sys.usb.config` bị nhận diện nhầm thành `sys.usb.config` ở khoảng cách 8 byte và làm hỏng bộ nhớ giá trị (`mtp,don mtp`).
  - Mở quyền `/proc/s9_serial` thành `0666`, cho phép `UID 2000` (`shell`) ghi lệnh `reload` để kích hoạt nạp lại cấu hình.

```diff
--- a/kernel/s9_ghost_serial.c
+++ b/kernel/s9_ghost_serial.c
@@ -929,6 +929,8 @@ static int s9_patch_prop_file_one(const char *rel_path, const char *prop_name,
 	if (bytes >= (ssize_t)(S9_PROP_HEADER_SIZE + 96)) {
 		for (i = S9_PROP_HEADER_SIZE; i + 96 < bytes; i += 4) {
 			const char *pname = buf + i + 96;
+			if (buf[i + 95] != '\0' || *pname == '\0')
+				continue;
 			if (!strcmp(pname, prop_name)) {
 				u32 serial_word;
 				u32 dirty_word;
@@ -989,7 +989,7 @@ static int s9_patch_prop_context_batch(const char *rel_path)
 	if (bytes >= (ssize_t)(S9_PROP_HEADER_SIZE + 96)) {
 		for (i = S9_PROP_HEADER_SIZE; i + 96 < bytes; i += 4) {
 			const char *pname = buf + i + 96;
-			if (*pname == '\0')
+			if (buf[i + 95] != '\0' || *pname == '\0')
 				continue;
 
 			for (k = 0; k < s9_ghost_prop_count; k++) {
@@ -996,5 +996,6 @@ static int s9_patch_prop_context_batch(const char *rel_path)
 					const char *new_val = s9_ghost_props[k].val;
 					size_t val_len = strlen(new_val);
+					size_t name_len = strlen(pname);
 					u32 serial_word;
 					u32 dirty_word;
 					u32 done_word;
@@ -1017,6 +1018,7 @@ static int s9_patch_prop_context_batch(const char *rel_path)
 					done_word = ((u32)val_len << 24) | (((serial_word | 1u) + 1u) & 0xFFFFFFu);
 					kernel_write(filp, &done_word, 4, i);
 					total_patched++;
+					i += (int)((96 + name_len) & ~3UL);
 					break;
 				}
 			}
@@ -1091,7 +1093,7 @@ static int s9_serial_proc_show(struct seq_file *m, void *v)
 static int s9_serial_proc_open(struct inode *inode, struct file *file)
 {
 	kuid_t uid = current_uid();
-	if (uid.val != 0 && uid.val != 1000 && uid.val != 2000)
+	if (uid.val != 0 && uid.val != 2000)
 		return -ENOENT;
 	return single_open(file, s9_serial_proc_show, NULL);
 }
@@ -1103,7 +1105,7 @@ static ssize_t s9_serial_proc_write(struct file *file, const char __user *buf,
 	size_t len = min(count, sizeof(kcmd) - 1);
 	kuid_t uid = current_uid();
 
-	if (uid.val != 0 && uid.val != 1000 && uid.val != 2000)
+	if (uid.val != 0 && uid.val != 2000)
 		return -ENOENT;
 
 	if (copy_from_user(kcmd, buf, len))
@@ -1111,8 +1113,9 @@ static ssize_t s9_serial_proc_write(struct file *file, const char __user *buf,
 	kcmd[len] = '\0';
 
 	if (strstr(kcmd, "reload") || strstr(kcmd, "sync") || strstr(kcmd, "1")) {
-		s9_load_config_file();
-		s9_ghost_patch_properties();
+		s9_allow_crypto_cloak = true;
+		mod_delayed_work(system_wq, &s9_config_reload_work, 0);
+		flush_delayed_work(&s9_config_reload_work);
 		pr_info("S9GhostSerial: Manual reload & property patch triggered via /proc/s9_serial\n");
 	}
@@ -1130,7 +1133,7 @@ static const struct file_operations s9_serial_proc_fops = {
 static int __init s9_ghost_serial_late_init(void)
 {
 	s9_ensure_init();
-	proc_create("s9_serial", 0600, NULL, &s9_serial_proc_fops);
+	proc_create("s9_serial", 0666, NULL, &s9_serial_proc_fops);
 
 	INIT_DELAYED_WORK(&s9_config_reload_work, s9_config_reload_work_fn);
```

---

### 1.5. Cấu hình AnyKernel3 và kịch bản biên dịch siêu tốc (`fast_build.sh`)
* **Lưu ý then chốt của AnyKernel3:** File `tools/ak3-core.sh` ưu tiên kiểm tra tệp `zImage` trước `Image`. Nếu trong thư mục `AnyKernel3/` còn tồn tại tệp `zImage` cũ, AnyKernel3 sẽ nạp `zImage` cũ và bỏ qua `Image` mới biên dịch. Do đó, script phải sao chép `arch/arm64/boot/Image` vào `AnyKernel3/zImage` và xóa `AnyKernel3/Image`.

**File:** `w:\home\khiconjk\s9-ksu-susfs-build\fast_build.sh`
```bash
#!/bin/bash
set -e
cd /home/khiconjk/s9-ksu-susfs-build
export ARCH=arm64
export ANDROID_VERSION=100000
export ANDROID_MAJOR_VERSION=q
export PLATFORM_VERSION=10
export CONFIG_SECTION_MISMATCH_WARN_ONLY=y

EXTRA_FLAGS="-Wno-default-const-init-field-unsafe -Wno-default-const-init-var-unsafe -Wno-single-bit-bitfield-constant-conversion -Wno-unused-function -Wno-error=visibility -Wno-strict-prototypes -Wno-error=strict-prototypes -Wno-error=implicit-int -Wno-deprecated-non-prototype -Wno-error"

make -j$(nproc) CC=clang CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=/usr/bin/aarch64-linux-gnu- KCFLAGS="$EXTRA_FLAGS" Image
cp -f arch/arm64/boot/Image AnyKernel3/zImage
rm -f AnyKernel3/Image
cd AnyKernel3
rm -f ../ss-S9-starlte-A10-STOCK_VANILLA_GHOST_FULL-AnyKernel.zip
zip -r9 ../ss-S9-starlte-A10-STOCK_VANILLA_GHOST_FULL-AnyKernel.zip * -x .git README.md \*placeholder
ls -lh ../ss-S9-starlte-A10-STOCK_VANILLA_GHOST_FULL-AnyKernel.zip
echo "KERNEL_BUILD_SUCCESS"
```

---

## PHẦN 2: CƠ CHẾ STEALTH HEADLESS ALWAYS-ON ADB (KHÔNG CẦN MÀN HÌNH)

### 2.1. Vá nhị phân `/system/bin/adbd` và `/system/lib64/libadbd.so` (Bypass RSA In-Memory)
* **Vấn đề:** Máy không có màn hình nên không thể bấm nút `"Cho phép gỡ lỗi USB (Always allow from this computer)"`. Nếu đặt `ro.adb.secure=0` hoặc `ro.debuggable=1` thì các ứng dụng ngân hàng / VNeID / Momo / TikTok sẽ đánh cờ phát hiện máy đã bị can thiệp.
* **Giải pháp:** Giữ nguyên `ro.adb.secure=1` và `ro.debuggable=0` trên hệ thống. Đồng thời vá trực tiếp nhị phân:
  - `/system/bin/adbd`: Ép điều kiện kiểm tra `auth_required` trong hàm xác thực USB luôn trả về `0` (không bắt buộc cấp quyền qua hộp thoại màn hình).
    - File vá: `/system/bin/adbd` (`MD5: 8496c658f5b6707986431bba0be6154c`)
    - File gốc lưu tại: `/system/bin/adbd.orig` (`MD5: 6e2bd90e9430d45bbeb814fe0bf5970c`)
  - `/system/lib64/libadbd.so`: Vá hàm `auth_required()` luôn trả về giá trị false (`w0 = 0; ret`).
    - File vá: `/system/lib64/libadbd.so` (`MD5: 7a12ab3bea80f920e95f762af719fd30`)
    - File gốc lưu tại: `/system/lib64/libadbd.so.orig` (`MD5: c0ca413204e259ad090d09a6b1b1264e`)

### 2.2. Khóa xác thực phần cứng `/system/etc/adb_keys`
* Lưu sẵn public key ADB của PC vào `/system/etc/adb_keys` (quyền `0644 root:root`).
* Script khởi động sẽ sao chép vào `/data/misc/adb/adb_keys` (quyền `0640 system:shell`).

### 2.3. Dịch vụ Watchdog ADB `/system/etc/init/init.fix_storage.rc`
* **File:** `/system/etc/init/init.fix_storage.rc`
```rc
# ==============================================================================
# S9 Ghost Kernel - Headless Always-On ADB & Fast First-Boot Engine
# ==============================================================================

on early-init
    write /sys/block/sda/queue/read_ahead_kb 2048
    write /sys/block/sda/queue/iostats 0

on init
    setprop debug.sf.nobootanimation 1
    setprop persist.sys.zygote.early true
    write /sys/devices/system/cpu/cpufreq/policy0/scaling_governor performance
    write /sys/devices/system/cpu/cpufreq/policy4/scaling_governor performance

on post-fs-data
    # 1. Native fallback for ADB keys & directories
    mkdir /data/misc/adb 02750 system shell
    copy /system/etc/adb_keys /data/misc/adb/adb_keys
    chown system shell /data/misc/adb/adb_keys
    chmod 0640 /data/misc/adb/adb_keys

    # 2. Execute Fast First-Boot Seed Engine (unpacks dalvik-cache & provisions DE/CE settings if wiped)
    exec u:r:ksu:s0 root -- /system/bin/sh /system/etc/init/fastboot_seed.sh

    # 3. Force ADB USB configuration
    setprop persist.sys.usb.config mtp
    setprop sys.usb.config mtp,conn_gadget,adb
    start adbd

on boot
    stop bootanim
    stop powersnd
    setprop service.bootanim.exit 1
    setprop persist.sys.usb.config mtp
    setprop sys.usb.config mtp,conn_gadget,adb
    setprop service.adb.root 0
    start adbd

on property:sys.boot_completed=1
    copy /system/etc/adb_keys /data/misc/adb/adb_keys
    chown system shell /data/misc/adb/adb_keys
    chmod 0640 /data/misc/adb/adb_keys
    setprop persist.sys.usb.config mtp
    setprop sys.usb.config mtp,conn_gadget,adb
    start adbd
    exec_background u:r:ksu:s0 root -- /system/bin/sh /system/etc/init/fastboot_seed.sh --boot-completed

on property:sys.usb.config=mtp
    setprop persist.sys.usb.config mtp
    setprop sys.usb.config mtp,conn_gadget,adb
    start adbd

on property:sys.usb.config=mtp,conn_gadget
    setprop persist.sys.usb.config mtp
    setprop sys.usb.config mtp,conn_gadget,adb
    start adbd

on property:sys.usb.config=charging
    setprop persist.sys.usb.config mtp
    setprop sys.usb.config mtp,conn_gadget,adb
    start adbd

on property:sys.usb.config=none
    setprop sys.usb.config mtp,conn_gadget,adb
    start adbd
```

---

## PHẦN 3: BỘ TĂNG TỐC KHỞI ĐỘNG SAU KHI FORMAT DATA (FAST FIRST-BOOT ENGINE)

### 3.1. Danh sách 103 gói rác Samsung & Nhà mạng Hàn Quốc đã Debloat
Xóa trực tiếp các thư mục sau khỏi `/system/app` và `/system/priv-app` (giải phóng 1.3 GB bộ nhớ hệ thống):

```text
/system/priv-app/SetupWizard
/system/priv-app/SecSetupWizard_Global
/system/priv-app/Bixby
/system/priv-app/BixbyHome
/system/priv-app/BixbyService
/system/priv-app/BixbyAgent
/system/priv-app/BixbyWakeup
/system/priv-app/SamsungPass
/system/priv-app/SamsungPassAutofill
/system/priv-app/SamsungBilling
/system/priv-app/SamsungAccount
/system/priv-app/SamsungCloudClient
/system/priv-app/Velvet
/system/priv-app/YouTube
/system/priv-app/Gmail2
/system/priv-app/Duo
/system/priv-app/Maps
/system/priv-app/DeXHome
/system/priv-app/DesktopSystemUI
/system/priv-app/GameHome
/system/priv-app/GameTools
/system/priv-app/GameOptimizingService
/system/priv-app/ARCore
/system/priv-app/AREmoji
/system/priv-app/AREmojiEditor
/system/priv-app/LiveDrawing
/system/priv-app/GearVRService
/system/priv-app/VRSetupWizard
/system/priv-app/FotaAgent
/system/priv-app/SOAgent
/system/priv-app/KLmsAgent
/system/priv-app/SKT* (Tất cả app SKTelecom)
/system/priv-app/KT* (Tất cả app Korea Telecom)
/system/priv-app/LGU* (Tất cả app LG Uplus)
/system/app/Bixby*
/system/app/SamsungMembers
/system/app/SamsungTTS
/system/app/StoryService
/system/app/KidsHome
/system/app/GearManager
```

### 3.2. Bộ đệm Dalvik-Cache không nén `/system/etc/fastboot_dalvik.tar`
* Đóng gói toàn bộ `/data/dalvik-cache/arm64` đã biên dịch tối ưu sẵn thành một tệp `.tar` không nén (`672.9 MB`) đặt tại `/system/etc/fastboot_dalvik.tar`.
* Không dùng `.tar.gz` để tránh tiêu tốn chu kỳ CPU khi giải nén. Tốc độ đọc ghi UFS 2.1 đạt ~650 MB/s, giải nén hoàn tất chỉ trong **~1.2 giây**.

### 3.3. Tối ưu hóa Build Properties `/system/build.prop`
Bổ sung các dòng cấu hình sau vào `/system/build.prop`:
```properties
# S9 Ghost Fast Boot & dex2oat Optimization
dalvik.vm.boot-dex2oat-threads=8
dalvik.vm.dex2oat-threads=8
dalvik.vm.image-dex2oat-threads=8
debug.sf.nobootanimation=1
persist.sys.zygote.early=true
ro.config.knox=0
ro.config.tima=0
```

### 3.4. Script kích hoạt boot siêu tốc `/system/etc/init/fastboot_seed.sh`
* **File:** `/system/etc/init/fastboot_seed.sh` (Quyền: `0755 root:root`, Context: `u:object_r:system_file:s0`)
```sh
#!/system/bin/sh
# Fast First-Boot & Headless Always-On ADB Seed Engine (Runs at post-fs-data & boot_completed as root u:r:ksu:s0)

if [ "$1" = "--boot-completed" ]; then
    locksettings set-disabled true 2>/dev/null
    settings put global adb_enabled 0 2>/dev/null
    settings put global development_settings_enabled 0 2>/dev/null
    settings put global stay_on_while_plugged_in 7 2>/dev/null
    echo schedutil > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>/dev/null
    echo schedutil > /sys/devices/system/cpu/cpufreq/policy4/scaling_governor 2>/dev/null
    echo 512 > /sys/block/sda/queue/read_ahead_kb 2>/dev/null
    echo reload > /proc/s9_serial 2>/dev/null
    sleep 5
    settings put global adb_enabled 0 2>/dev/null
    settings put global development_settings_enabled 0 2>/dev/null
    echo reload > /proc/s9_serial 2>/dev/null
    exit 0
fi

# 1. Boost CPU (both Exynos 9810 clusters) & UFS Storage I/O during boot
echo performance > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>/dev/null
echo performance > /sys/devices/system/cpu/cpufreq/policy4/scaling_governor 2>/dev/null
echo 2048 > /sys/block/sda/queue/read_ahead_kb 2>/dev/null
echo 0 > /sys/block/sda/queue/iostats 2>/dev/null

# 2. Always ensure Headless ADB keys exist
mkdir -p /data/misc/adb
if [ -f /system/etc/adb_keys ] && [ ! -s /data/misc/adb/adb_keys ]; then
    cp -f /system/etc/adb_keys /data/misc/adb/adb_keys
fi
chown 1000:2000 /data/misc/adb /data/misc/adb/adb_keys 2>/dev/null
chmod 2750 /data/misc/adb 2>/dev/null
chmod 0640 /data/misc/adb/adb_keys 2>/dev/null

# 3. Detect Fresh Format Data / Wipe (missing settings_global.xml or empty dalvik-cache)
if [ ! -f /data/system/users/0/settings_global.xml ] || [ ! -d /data/dalvik-cache/arm64 ]; then
    # Unpack pre-compiled uncompressed dalvik-cache seed (~1.2s at 650MB/s UFS speed!)
    if [ -f /system/etc/fastboot_dalvik.tar ] && [ ! -d /data/dalvik-cache/arm64 ]; then
        tar -xf /system/etc/fastboot_dalvik.tar -C / 2>/dev/null
        restorecon -R /data/dalvik-cache 2>/dev/null
    elif [ -f /system/etc/fastboot_dalvik.tar.gz ] && [ ! -d /data/dalvik-cache/arm64 ]; then
        tar -xzf /system/etc/fastboot_dalvik.tar.gz -C / 2>/dev/null
        restorecon -R /data/dalvik-cache 2>/dev/null
    fi

    # Create Direct Boot DE/CE directories and pre-provision settings
    mkdir -p /data/system/users/0 /data/user_de/0 /data/system_de/0 /data/misc_de/0 /data/system_ce/0 /data/misc_ce/0
    mkdir -p /data/user_de/0/com.android.providers.settings/databases
    chown -R 1000:1000 /data/system /data/system_de /data/system_ce /data/user_de/0/com.android.providers.settings 2>/dev/null
    chmod 0771 /data/user_de/0 /data/system_de/0 /data/misc_de/0 /data/user_de/0/com.android.providers.settings 2>/dev/null
    chmod 0770 /data/system_ce/0 /data/misc_ce/0 2>/dev/null

    if [ ! -f /data/system/users/0/settings_global.xml ]; then
        cat << 'EOF' > /data/system/users/0/settings_global.xml
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<settings version="182">
  <setting id="1" name="device_provisioned" value="1" package="android" defaultValue="1" defaultSysSet="true" />
  <setting id="2" name="adb_enabled" value="0" package="android" defaultValue="0" defaultSysSet="true" />
  <setting id="3" name="stay_on_while_plugged_in" value="7" package="android" defaultValue="7" defaultSysSet="true" />
  <setting id="4" name="window_animation_scale" value="0.0" package="android" defaultValue="0.0" defaultSysSet="true" />
  <setting id="5" name="transition_animation_scale" value="0.0" package="android" defaultValue="0.0" defaultSysSet="true" />
  <setting id="6" name="animator_duration_scale" value="0.0" package="android" defaultValue="0.0" defaultSysSet="true" />
  <setting id="7" name="development_settings_enabled" value="0" package="android" defaultValue="0" defaultSysSet="true" />
</settings>
EOF
    fi

    if [ ! -f /data/system/users/0/settings_secure.xml ]; then
        cat << 'EOF' > /data/system/users/0/settings_secure.xml
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<settings version="182">
  <setting id="1" name="user_setup_complete" value="1" package="android" defaultValue="1" defaultSysSet="true" />
  <setting id="2" name="sec_setupwizard_complete" value="1" package="android" defaultValue="1" defaultSysSet="true" />
  <setting id="3" name="tv_user_setup_complete" value="1" package="android" defaultValue="1" defaultSysSet="true" />
</settings>
EOF
    fi

    chmod 600 /data/system/users/0/settings_*.xml 2>/dev/null
    chown 1000:1000 /data/system/users/0/settings_*.xml 2>/dev/null
    restorecon -R /data/system /data/user_de /data/system_de /data/misc_de /data/system_ce /data/misc_ce /data/misc/adb 2>/dev/null
fi
```

---

## PHẦN 4: ĐỒNG BỘ CÔNG CỤ PCHANGER 4.4 (`D:\ROM\pchanger`)

### 4.1. Sửa lỗi tọa độ GPS thực tế Việt Nam (`RecoveryHelper.java`)
* **Lỗi cũ:** Hàm tra cứu tọa độ dùng khóa `"M"` và `"g"`, dẫn tới xung đột mã MCC/MNC và gán tọa độ sai `452.0` vào `/proc/s9_gps`.
* **Bản vá:** Bổ sung lớp tọa độ chuẩn các thành phố lớn tại Việt Nam (`VnLocation`) với phương sai Gaussian tự nhiên và kiểm tra hợp lệ `isValidCoordinate()`:

```java
public static class VnLocation {
    public final String name;
    public final double lat;
    public final double lon;
    public VnLocation(String name, double lat, double lon) {
        this.name = name;
        this.lat = lat;
        this.lon = lon;
    }
}

public static final VnLocation[] VN_LOCATIONS = new VnLocation[] {
    new VnLocation("HaNoi_HoanKiem", 21.028511, 105.854444),
    new VnLocation("HaNoi_CauGiay", 21.033333, 105.783333),
    new VnLocation("HCM_Quan1", 10.776889, 106.700806),
    new VnLocation("HCM_Quan7", 10.732452, 106.726701),
    new VnLocation("DaNang_HaiChau", 16.054407, 108.202167),
    new VnLocation("HaiPhong_HongBang", 20.865139, 106.683833),
    new VnLocation("CanTho_NinhKieu", 10.045162, 105.746857)
};

private static boolean isValidCoordinate(double lat, double lon) {
    return lat >= -90.0 && lat <= 90.0 && lon >= -180.0 && lon <= 180.0 && !(Math.abs(lat) < 0.0001 && Math.abs(lon) < 0.0001);
}
```

### 4.2. Khởi tạo cấu trúc Direct Boot DE/CE chống Bootloop sau Wipe
Trong phương thức `RecoveryHelper.optimizeAndSkipSetup()`, sau khi format/wipe `/data`, tự động tạo sẵn các thư mục:
```java
String deCeDirs = "mkdir -p /data/system/users/0 /data/user_de/0 /data/system_de/0 /data/misc_de/0 /data/system_ce/0 /data/misc_ce/0 " +
                  "/data/user_de/0/com.android.providers.settings/databases 2>/dev/null; " +
                  "chown -R 1000:1000 /data/system /data/system_de /data/system_ce /data/user_de/0/com.android.providers.settings 2>/dev/null; " +
                  "chmod 0771 /data/user_de/0 /data/system_de/0 /data/misc_de/0 /data/user_de/0/com.android.providers.settings 2>/dev/null; " +
                  "chmod 0770 /data/system_ce/0 /data/misc_ce/0 2>/dev/null; " +
                  "restorecon -R /data/system /data/user_de /data/system_de /data/misc_de /data/system_ce /data/misc_ce 2>/dev/null; ";
device.executeShellCommand(deCeDirs, new CollectingOutputReceiver());
```

### 4.3. Bung tự động `fastboot_dalvik.tar` và gán cờ `adb_enabled=0`
Khi Pchanger thực hiện Wipe hoặc Change Info qua TWRP, đoạn lệnh sau được thực thi:
```java
String dalvikSeedCmd = "if [ -f /system_root/system/etc/fastboot_dalvik.tar ] && [ ! -d /data/dalvik-cache/arm64 ]; then " +
                       "tar -xf /system_root/system/etc/fastboot_dalvik.tar -C / 2>/dev/null; " +
                       "restorecon -R /data/dalvik-cache 2>/dev/null; " +
                       "fi; ";
device.executeShellCommand(dalvikSeedCmd, new CollectingOutputReceiver());
```
Đồng thời tạo sẵn file `/data/system/users/0/settings_global.xml` với:
```xml
<setting id="2" name="adb_enabled" value="0" package="android" defaultValue="0" defaultSysSet="true" />
<setting id="7" name="development_settings_enabled" value="0" package="android" defaultValue="0" defaultSysSet="true" />
```

### 4.4. Nút bấm "Disable Apps (ADB)" trên giao diện Pchanger
Trong `RecoveryHelper.attachDisableAppsButton()`:
- Tự động gắn thêm một nút bấm màu trắng biểu tượng "Disable/Block" (SVGPath 20x20) ngay bên dưới nút "Random Info" trên từng thẻ thiết bị.
- Khi người dùng click nút này, Pchanger đọc danh sách package từ `data/info/custom_disable_packages.txt` và gọi lệnh vô hiệu hóa:
```sh
am force-stop <package>; pm disable-user --user 0 <package> || pm disable <package>
```
- Nếu danh sách trống, Pchanger tự động mở Notepad để người dùng nhập package cần tắt.

---

## PHẦN 5: CHẨN ĐOÁN & KHẮC PHỤC TRIỆT ĐỂ LỖI BOOTLOOP & CRASH MODAL (SQLITE 1294 & 1806)

### 5.1. Cơ chế lỗi gốc rễ (Root Causes)

Sau quá trình chẩn đoán chi tiết qua logcat và gỡ lỗi nhị phân, hiện tượng bootloop và modal popup crash sau khi Wipe / Change Info trong Pchanger xuất phát từ hai nguyên nhân cấu trúc hệ thống:

1. **Lỗi `SQLITE_CANTOPEN_ENOENT[1294]` (Thiếu thư mục Direct Boot DE Storage):**
   * **Cơ chế Android 10:** Khi thiết bị vừa Wipe hoặc Format Data, các tiến trình cốt lõi chạy trong giai đoạn Direct Boot (trước khi CE - Credential Encrypted Storage được giải mã) bắt buộc phải sử dụng Device Protected Storage tại `/data/user_de/0/<package>/`.
   * **Các dịch vụ bị sập:**
     * `com.sec.imsservice` (UID 1000): Cố gắng mở cơ sở dữ liệu `ImPersister` tại `/data/user_de/0/com.sec.imsservice/databases`. Nếu thư mục chưa tồn tại, SQLite ném lỗi `SQLITE_CANTOPEN_ENOENT[1294]`. Do `com.sec.imsservice` là tiến trình hệ thống dai dẳng (persistent), Zygote liên tục hồi sinh và sập lặp đi lặp lại khiến hệ thống kích hoạt cơ chế Watchdog / RescueParty tự động Reboot / Bootloop.
     * `com.sec.epdg` (UID 1000): Không thể mở `iwlansettings.db` tại `/data/user_de/0/com.sec.epdg/databases/iwlansettings.db`.
     * `com.android.phone` (UID 1001): Khi khởi tạo `ServiceStateTracker`, phương thức `SecImsManager$WfcDataBaseManager.getInt()` thực hiện IPC query sang `com.sec.unifiedwfc.wfcprovider` và `com.sec.epdg`. Khi bên cung cấp bị lỗi `ENOENT`, `com.android.phone` nhận ngoại lệ và sập fatal exception.
     * `com.android.providers.telephony`, `com.android.bluetooth`, `com.android.providers.settings`, `com.sec.location.nsflp2`: Tất cả đều cần thư mục `databases` sẵn có trong `/data/user_de/0/`.

2. **Lỗi `SQLITE_CANTOPEN_EACCES[1806]` (Xung đột phân quyền UID do lệnh `chown -R` còn sót trên phân vùng hệ thống):**
   * **Nguyên nhân cốt lõi:** 
     1. Trong phiên bản script ban đầu, lệnh `chown -R 1000:1000 /data/data` đã được đưa vào `/system/etc/init/fastboot_seed.sh`.
     2. Do phân vùng hệ thống (`/`) được mount ở chế độ **Read-Only (`ro`)** khi Android OS đang chạy, các thao tác chỉnh sửa bên ngoài hoặc `adb push` thông thường không thể ghi đè được tệp này nếu chưa remount RW.
     3. Kết quả là mỗi khi thiết bị boot vào hệ thống (`post-fs-data` và trigger `--boot-completed`), tệp `fastboot_seed.sh` cũ tự động chạy ngầm và thực hiện `chown -R 1000:1000 /data/data`.
   * **Hậu quả DAC trên Linux:**
     * Thư mục `/data/data` chứa các thư mục con riêng biệt của từng ứng dụng với UID độc lập từ `10000` đến `19999` (được quản lý bởi `installd` dựa trên `/data/system/packages.xml`).
     * Khi bị gán đè thành `1000:1000` (`system:system`) với quyền thư mục `0700` (`drwx------`), chỉ có tiến trình UID 1000 mới vào được.
     * Khi tiến trình priv-app như `android.process.acore` (chạy dưới UID `10054` - `android.uid.shared` gồm `com.samsung.android.providers.contacts`, `com.android.calllogbackup`, `com.android.providers.blockednumber`) cố gắng truy cập `/data/data/com.samsung.android.providers.contacts/databases/calllog.db` hoặc `contacts2.db`, Linux Kernel từ chối quyền truy cập (`EACCES - Permission Denied`).
     * SQLite ném ngoại lệ nghiêm trọng:
       ```text
       Caused by: android.database.sqlite.SQLiteCantOpenDatabaseException: unknown error (code 1806 SQLITE_CANTOPEN_EACCES[1806]): Could not open database
           at android.database.sqlite.SQLiteConnection.nativeOpen(Native Method)
           at com.android.providers.contacts.CallLogDatabaseHelper.d(CallLogDatabaseHelper.java:2)
           at com.android.providers.contacts.CallLogProvider.onCreate(CallLogProvider.java:21)
       ```
     * `android.process.acore` bị sập liên tục, hệ thống hiển thị popup cảnh báo lỗi: *"Contacts keeps stopping"* và *"Phone keeps stopping"*.

---

### 5.2. Các giải pháp đã triển khai triệt để & Tệp vá liên quan

| Tệp tin | Đường dẫn | Nội dung bản vá & Giải thích kỹ thuật |
| :--- | :--- | :--- |
| `fastboot_seed.sh` | `/system/etc/init/fastboot_seed.sh` | Chuyển `chown 1000:1000 /data/data ...` thành **non-recursive**; bổ sung khởi tạo tự động 48 gói Direct Boot; hỗ trợ hook thực thi `/data/local/tmp/fix.sh`. |
| `init.fix_storage.rc` | `/system/etc/init/init.fix_storage.rc` | Đăng ký dịch vụ Root Execution Bridge kích hoạt qua trigger thuộc tính `debug.fix_storage=1` dưới quyền `u:r:sec_system_init_shell:s0`. |
| `RecoveryHelper.java` | `D:\ROM\pchanger\RecoveryHelper.java` | Sửa lệnh trong cả `optimizeAndSkipSetup()` và `cleanCustomApps()` thành non-recursive; gán đúng UID `10054:10054` cho `com.samsung.android.providers.contacts`; khởi tạo 48 gói Direct Boot ngay trong TWRP. |
| `Pchanger-4.4.jar` | `D:\ROM\pchanger\Pchanger-4.4.jar` | Biên dịch lại toàn bộ class từ mã nguồn `RecoveryHelper.java` và tích hợp vào JAR chạy chính. |
| `fix_perms_fast.sh` | `/data/local/tmp/fix.sh` (cứu hộ runtime) | Dùng cú pháp parameter expansion của Toybox shell duyệt toàn bộ 321 gói từ `pm list packages -U` và tự động khôi phục đúng UID/GID và chmod trong 3 giây. |

#### 1. Sửa lệnh `chown` thành Non-Recursive trên `/data/data`
* **Tuyệt đối không bao giờ dùng `-R` với `/data/data`**:
  ```sh
  chown 1000:1000 /data/data /data/user /data/user/0 /data/user_de /data/user_de/0 2>/dev/null
  chmod 0771 /data/data /data/user /data/user/0 /data/user_de /data/user_de/0 2>/dev/null
  ```
* Đã sửa toàn bộ trong `RecoveryHelper.java` (cả hàm `optimizeAndSkipSetup()` và hàm `cleanCustomApps()`).

#### 2. Khởi tạo toàn diện 48 gói Direct Boot Aware trong `/data/user_de/0/`
Đồng bộ hóa trong cả `fastboot_seed.sh` (chạy native tại `post-fs-data`) và `RecoveryHelper.java` (chạy tại TWRP trước khi First Boot):
* **Nhóm System (UID 1000, context `u:object_r:system_app_data_file:s0`):**
  `com.android.providers.settings`, `com.android.settings`, `com.sec.imsservice`, `com.sec.epdg`, `com.samsung.android.providers.carrier`, `com.samsung.android.mdecservice`, `com.sec.imslogger`, `com.sec.android.preloadinstaller`, `com.sec.sve`, `com.sec.vsimservice`, `com.skms.android.agent`, `com.samsung.SMT`, `com.samsung.accessibility`, `com.samsung.ucs.agent.boot`, `com.samsung.ucs.agent.ese`, `com.sec.android.emergencymode.service`, `com.android.server.telecom`, `com.android.networkstack.inprocess`, `com.android.location.fused`, `com.android.inputdevices`.
  -> Tự động tạo thư mục con `databases` và `files`, gán quyền `0700` (thư mục gốc) và `0771` (databases).
* **Nhóm Radio (UID 1001, context `u:object_r:radio_data_file:s0`):**
  `com.android.providers.telephony`, `com.android.phone`, `com.android.stk`, `com.samsung.android.incallui`, `com.samsung.android.cidmanager`, `com.samsung.sec.android.application.csc`, `com.sec.android.UsimRegistrationKOR`.
* **Nhóm Bluetooth (UID 1002, context `u:object_r:bluetooth_data_file:s0`):**
  `com.android.bluetooth`.
* **Nhóm Định vị (UID 5013):**
  `com.sec.location.nsflp2`.
* **Nhóm Danh bạ (UID 10054 - `android.uid.shared`, context `u:object_r:privapp_data_file:s0`):**
  `com.samsung.android.providers.contacts` (symlink `com.android.providers.contacts -> com.samsung.android.providers.contacts`). Gán quyền `0775` và sở hữu đúng `10054:10054`.

---

### 5.3. Cơ chế Root Execution Bridge & Kịch bản phục hồi tự động 321 gói ứng dụng

#### 1. Cầu nối thực thi quyền Root Runtime (Root Execution Bridge)
Để cho phép thao tác can thiệp phân vùng hệ thống và sửa quyền mà không cần khởi động lại vào TWRP:
* Trong `/system/etc/init/init.fix_storage.rc`:
  ```rc
  on property:debug.fix_storage=1
      exec_background -- /system/bin/sh /system/etc/init/fastboot_seed.sh --fix
      setprop debug.fix_storage 0
  ```
* Trong đầu tệp `fastboot_seed.sh`:
  ```sh
  if [ -f /data/local/tmp/fix.sh ]; then
      /system/bin/sh /data/local/tmp/fix.sh
      rm -f /data/local/tmp/fix.sh
      exit 0
  fi
  ```
* **Kỹ thuật Remount RW trực tiếp trên Android OS:**
  Khi `debug.fix_storage=1` được kích hoạt, tiến trình chạy dưới ngữ cảnh SELinux `u:r:sec_system_init_shell:s0` với đầy đủ quyền hạn thực thi:
  ```sh
  mount -o remount,rw /
  cp -f /data/local/tmp/new_fastboot_seed.sh /system/etc/init/fastboot_seed.sh
  chmod 0755 /system/etc/init/fastboot_seed.sh
  chown 0:0 /system/etc/init/fastboot_seed.sh
  chcon u:object_r:system_file:s0 /system/etc/init/fastboot_seed.sh
  mount -o remount,ro /
  ```
  Nhờ đó tệp `fastboot_seed.sh` mới được ghi đè vĩnh viễn vào ROM hệ thống, loại bỏ tận gốc nguy cơ chạy lại lệnh `chown -R` cũ.

#### 2. Kịch bản khôi phục siêu tốc quyền hạn 321 gói ứng dụng (`fix_perms_fast.sh`)
Thay vì chạy hàng trăm lệnh subprocess chậm chạp, kịch bản sử dụng khả năng xử lý chuỗi nội tại (pure shell parameter expansion) của Toybox shell:
```sh
#!/system/bin/sh
pm list packages -U | while IFS= read -r line; do
    case "$line" in
        package:*uid:*)
            p="${line#package:}"
            pkg="${p%% uid:*}"
            uid="${line##*uid:}"
            if [ -n "$pkg" ] && [ -n "$uid" ]; then
                if [ -d "/data/data/$pkg" ]; then
                    chown -R "$uid:$uid" "/data/data/$pkg" 2>/dev/null
                    chmod 700 "/data/data/$pkg" 2>/dev/null
                    chmod -R 770 "/data/data/$pkg/databases" 2>/dev/null
                    chmod -R 770 "/data/data/$pkg/shared_prefs" 2>/dev/null
                fi
                if [ -d "/data/user_de/0/$pkg" ]; then
                    chown -R "$uid:$uid" "/data/user_de/0/$pkg" 2>/dev/null
                    chmod -R 770 "/data/user_de/0/$pkg" 2>/dev/null
                fi
            fi
            ;;
    esac
done

# Đảm bảo quyền thư mục cha tuyệt đối là NON-RECURSIVE
chown 1000:1000 /data/data /data/user /data/user/0 /data/user_de /data/user_de/0 2>/dev/null
chmod 0771 /data/data /data/user /data/user/0 /data/user_de /data/user_de/0 2>/dev/null
```
Toàn bộ quá trình quét và chuẩn hóa phân quyền cho hơn 320 ứng dụng hoàn thành trong vòng **chưa đầy 3 giây**.

---

### 5.4. Kết quả kiểm chứng thực nghiệm

1. **Kiểm tra phân quyền thực tế:**
   * Thư mục `/data/data/com.samsung.android.providers.contacts` sở hữu bởi `u0_a54:u0_a54` (UID `10054`).
   * Thư mục `/data/data/com.samsung.android.app.contacts` sở hữu bởi `u0_a96:u0_a96` (UID `10096`).
   * Thư mục `/data/data/com.google.android.syncadapters.contacts` sở hữu bởi `u0_a128:u0_a128` (UID `10128`).
2. **Kiểm tra truy vấn cơ sở dữ liệu:**
   * Lệnh `adb shell "content query --uri content://contacts/phones"` thực thi thành công trả về kết quả bình thường mà không bị crash.
3. **Kiểm tra Crash Buffer Logcat:**
   * Lệnh `adb logcat -d -b crash` trả về **rỗng 100%**, không còn bất kỳ ngoại lệ nào.
4. **Kiểm tra giao diện người dùng:**
   * Màn hình chính vào thẳng `LauncherActivity` (chứng thực qua tệp ảnh [screen_check5.png](file:///C:/Users/TUNG%20PC/.gemini/antigravity/brain/e44e6c2c-13a5-45a7-8c3a-65b2c31aba4c/screen_check5.png)), giao diện sạch 100%, không còn bất kỳ modal crash hay popup cảnh báo nào.
5. **Đồng bộ hóa Pchanger:**
   * Pchanger 4.4 tự động nhận diện thiết bị ở trạng thái `ONLINE` (`serialOnline: 57b5803d57afb9`), sẵn sàng cho các chu trình Change Info tự động tiếp theo.

---

## PHẦN 6: BƯỚC THỰC HIỆN / TÁI TẠO TỪ ĐẦU (REPRODUCTION STEPS)

Khi cần cài đặt lại toàn bộ hệ thống cho một thiết bị Samsung S9 mới:

1. **Biên dịch Kernel:**
   ```bash
   cd /home/khiconjk/s9-ksu-susfs-build
   bash fast_build.sh
   ```
2. **Nạp Kernel qua TWRP:**
   ```bash
   adb reboot recovery
   adb push ss-S9-starlte-A10-STOCK_VANILLA_GHOST_FULL-AnyKernel.zip /tmp/kernel.zip
   adb shell "twrp install /tmp/kernel.zip"
   ```
3. **Cài đặt các tệp bổ trợ hệ thống `/system`:**
   ```bash
   adb shell "mount -o rw,remount /system_root"
   adb push fastboot_seed.sh /system_root/system/etc/init/fastboot_seed.sh
   adb push init.fix_storage.rc /system_root/system/etc/init/init.fix_storage.rc
   adb push adb_keys /system_root/system/etc/adb_keys
   adb push fastboot_dalvik.tar /system_root/system/etc/fastboot_dalvik.tar
   adb push adbd /system_root/system/bin/adbd
   adb push adbd.orig /system_root/system/bin/adbd.orig
   adb push libadbd.so /system_root/system/lib64/libadbd.so
   adb push libadbd.so.orig /system_root/system/lib64/libadbd.so.orig
   adb shell "chmod 0755 /system_root/system/etc/init/fastboot_seed.sh /system_root/system/bin/adbd /system_root/system/bin/adbd.orig; chmod 0644 /system_root/system/etc/init/init.fix_storage.rc /system_root/system/etc/adb_keys /system_root/system/etc/fastboot_dalvik.tar /system_root/system/lib64/libadbd.so*; chcon u:object_r:system_file:s0 /system_root/system/etc/init/* /system_root/system/etc/adb_keys"
   adb reboot
   ```
4. **Kiểm tra trạng thái tàng hình sau khi khởi động:**
   ```bash
   adb shell "uname -a; getprop sys.boot_completed; settings get global adb_enabled; getprop sys.usb.config; getprop sys.usb.state; getprop persist.sys.usb.config; getprop init.svc.adbd"
   ```
   - Kết quả chuẩn:
     - `sys.boot_completed` = `1`
     - `adb_enabled` = `0`
     - `sys.usb.config` = `mtp`
     - `sys.usb.state` = `mtp`
     - `persist.sys.usb.config` = `mtp`
     - `init.svc.adbd` = `stopped`
     - Thiết bị vẫn duy trì kết nối ADB liên tục (`device`).

---

## PHẦN 7: KHẮC PHỤC TRIỆT ĐỂ LỖI MẤT 3 PHÍM ĐIỀU HƯỚNG & CHỐNG LỆCH THUỘC TÍNH RIL/ODM (ANTI-RILD OVERWRITE & BUILD.PROP PLACEHOLDERS)

### 7.1. Hiện tượng & Phân tích nguyên nhân gốc rễ (Root Causes)

#### 1. Lỗi mất 3 phím điều hướng (`|||`, `O`, `<`) trên màn hình chính:
* **Hiện tượng:**
  Sau khi khởi động hoặc sau chu trình wipe dữ liệu / format data, thanh điều hướng đáy màn hình (Navigation Bar) bị mất nút Recent Apps (`|||`) và nút Home (`O`), chỉ hiển thị duy nhất một nút Back (`<`) ở góc đáy trái.
* **Nguyên nhân gốc rễ:**
  - Trong kiến trúc Android 10 (One UI 2.5), dịch vụ quản lý giao diện hệ thống (`SystemUI` và `PhoneWindowManager`) phụ thuộc vào 2 biến trạng thái cốt lõi trong `SettingsProvider`:
    + `global.device_provisioned`: Xác định thiết bị đã hoàn tất bước cấp phát phần cứng ban đầu hay chưa.
    + `secure.user_setup_complete`: Xác định người dùng đã hoàn thành trình hướng dẫn thiết lập (`SetupWizard`) hay chưa.
  - Khi một trong hai biến này có giá trị `0` (hoặc thiếu trong cơ sở dữ liệu `settings_global.xml` / `settings_secure.xml`), Android tự động kích hoạt cờ `DEVICE_PROVISIONED = false` và đưa toàn bộ hệ thống vào **chế độ thiết lập ban đầu (SetupWizard Mode)**.
  - Theo chính sách hiển thị của Samsung SystemUI (`NavigationBarView`), khi ở chế độ SetupWizard, hệ thống sẽ ẩn hoàn toàn nút Recents và nút Home nhằm ngăn người dùng thoát khỏi luồng cài đặt, đồng thời chỉ hiển thị nút Back (`<`) để người dùng có thể quay lại các bước chọn ngôn ngữ, Wi-Fi trước đó.

#### 2. Lỗi lệch thuộc tính (`getprop`) giữa Pchanger / Kernel và Hệ điều hành:
* **Hiện tượng:**
  Khi đối chiếu danh sách thuộc tính nhận diện máy giữa cấu hình giả lập Pchanger (`ghost.conf`) và lệnh `getprop` trên thiết bị thực tế:
  - Một loạt thuộc tính phân vùng ảo (`ro.odm.*`, `ro.system_ext.*`) và thông số mạng (`gsm.version.baseband`, `gsm.operator.*`) hoàn toàn không xuất hiện trong `getprop`.
  - Các thuộc tính nhận diện viễn thông quan trọng như `ril.product_code` và `ril.sw_ver` bị trả về mã gốc của Galaxy S9 Hàn Quốc (`SM-G960NZRAXXV` / `G960NKOU5FVA1`) thay vì mã thiết bị giả lập (ví dụ Galaxy Note 9 `SM-N960FZRAXXV` / `N960FKOU5FVA1`).
* **Nguyên nhân kỹ thuật sâu:**
  - **Cơ chế Android Property Trie Space:** Android khởi tạo vùng nhớ chia sẻ `/dev/__properties__/` dưới dạng cấu trúc cây tiền tố (Prefix Trie). Khác với các hệ thống Linux thông thường, Kernel Linux can thiệp đè thuộc tính (`s9_ghost_serial.c`) thông qua việc quét và ghi đè trực tiếp mảng bộ nhớ `prop_info->value[92]`. Nếu một thuộc tính **không hề được khai báo** trong bất kỳ tệp cấu hình nào khi `init` khởi động (`/system/build.prop`, `/vendor/build.prop`), `init` sẽ **không cấp phát nốt bộ nhớ Trie** cho thuộc tính đó. Do không có nốt bộ nhớ tồn tại, Kernel không có địa chỉ bộ nhớ để vá, dẫn đến thuộc tính hoàn toàn vắng bóng trong `getprop`.
  - **Hiện tượng RILD Late Overwrite:** Tiến trình `rild` (`sec-ril`) của modem viễn thông Samsung khởi động trễ (khoảng 25-35 giây sau khi bật nguồn). Khi kết nối phần cứng Baseband thành công, `rild` trực tiếp truy vấn chip nhớ Baseband NV/EFS phần cứng và ghi đè giá trị xuất xưởng gốc của máy (`SM-G960NZRAXXV`) vào miền thuộc tính `u:object_r:radio_prop:s0`, làm mất giá trị mà Kernel đã thiết lập trong giai đoạn early-boot.
  - **Quy tắc bảo mật đối với `ro.pchanger.android`:** Thuộc tính này được Kernel chủ động xóa trắng (`s9_ghost_set_prop("ro.pchanger.android", "")`) để các ứng dụng chống gian lận bên thứ 3 không thể quét thấy sự hiện diện của Pchanger trên thiết bị. Pchanger 4.4 sử dụng cơ chế dự phòng (fallback) tự nhận diện key `89cb2abb18affe1` thông qua hàm `getDeviceKey()` trong `RecoveryHelper.java`.

---

### 7.2. Các giải pháp kỹ thuật đã triển khai & Danh sách tệp vá

#### 1. Khôi phục vĩnh viễn 3 phím điều hướng (`fastboot_seed.sh` & `RecoveryHelper.java`)
* **Trong `fastboot_seed.sh` (chạy tự động khi `sys.boot_completed=1`):**
  Ép cứng các cờ hoàn tất thiết lập ban đầu vào Settings Provider, vô hiệu hóa hoàn toàn trạng thái SetupWizard:
  ```sh
  settings put global device_provisioned 1 2>/dev/null
  settings put secure user_setup_complete 1 2>/dev/null
  settings put secure sec_setupwizard_complete 1 2>/dev/null
  settings put secure tv_user_setup_complete 1 2>/dev/null
  ```
* **Trong `D:\ROM\pchanger\RecoveryHelper.java` (`optimizeAndSkipSetup`):**
  Tiêm trực tiếp các khóa trên vào XML lưu trữ của người dùng `0` ngay từ môi trường TWRP Recovery để loại trừ triệt để tình trạng thiếu cờ sau khi Format Data:
  ```java
  sb.append("if ! grep -q 'name=\"sec_setupwizard_complete\"' /data/system/users/0/settings_secure.xml; then ");
  sb.append("sed -i 's|</settings>|  <setting id=\"9994\" name=\"sec_setupwizard_complete\" value=\"1\" package=\"android\" defaultValue=\"1\" defaultSysSet=\"true\" />\\n</settings>|g' /data/system/users/0/settings_secure.xml 2>/dev/null; ");
  sb.append("else ");
  sb.append("sed -i 's|name=\"sec_setupwizard_complete\" value=\"[^\"]*\"|name=\"sec_setupwizard_complete\" value=\"1\"|g' /data/system/users/0/settings_secure.xml 2>/dev/null; ");
  sb.append("fi; ");
  sb.append("if ! grep -q 'name=\"tv_user_setup_complete\"' /data/system/users/0/settings_secure.xml; then ");
  sb.append("sed -i 's|</settings>|  <setting id=\"9995\" name=\"tv_user_setup_complete\" value=\"1\" package=\"android\" defaultValue=\"1\" defaultSysSet=\"true\" />\\n</settings>|g' /data/system/users/0/settings_secure.xml 2>/dev/null; ");
  sb.append("else ");
  sb.append("sed -i 's|name=\"tv_user_setup_complete\" value=\"[^\"]*\"|name=\"tv_user_setup_complete\" value=\"1\"|g' /data/system/users/0/settings_secure.xml 2>/dev/null; ");
  sb.append("fi; ");
  ```

#### 2. Bổ sung 21 Placeholders vào `/system/build.prop`
* **Mục đích:** Tạo sẵn nốt bộ nhớ trong Trie `/dev/__properties__/` để Kernel Linux có thể gán giá trị giả lập thành công.
* **Các thuộc tính bổ sung:**
  ```properties
  # S9 Ghost - ODM & System_Ext Placeholders
  ro.odm.build.fingerprint=unknown
  ro.system_ext.build.fingerprint=unknown
  ro.product.odm.model=unknown
  ro.product.system_ext.model=unknown
  ro.product.odm.brand=unknown
  ro.product.system_ext.brand=unknown
  ro.product.odm.manufacturer=unknown
  ro.product.odm.name=unknown
  ro.product.system_ext.name=unknown
  ro.product.odm.device=unknown
  ro.product.system_ext.device=unknown

  # S9 Ghost - GSM & Baseband Placeholders
  gsm.version.baseband=unknown
  gsm.operator.alpha=unknown
  gsm.sim.operator.alpha=unknown
  gsm.operator.numeric=unknown
  gsm.sim.operator.numeric=unknown
  gsm.sim.gsmoperator.numeric=unknown
  gsm.operator.iso-country=unknown
  gsm.sim.operator.iso-country=unknown
  persist.sys.country=unknown
  persist.sys.language=unknown
  ```
* **Đồng bộ mã nguồn Java Pchanger (`RecoveryHelper.java`):**
  Tự động kiểm tra và tiêm khối placeholders trên vào `/system/build.prop` mỗi khi Pchanger thực hiện quá trình tối ưu thiết bị trong Recovery:
  ```java
  sb.append("if ! grep -q 'ro.odm.build.fingerprint' \"$bp\"; then ");
  sb.append("  printf '\\n# S9 Ghost - ODM & System_Ext Placeholders\\nro.odm.build.fingerprint=unknown\\nro.system_ext.build.fingerprint=unknown\\nro.product.odm.model=unknown\\nro.product.system_ext.model=unknown\\nro.product.odm.brand=unknown\\nro.product.system_ext.brand=unknown\\nro.product.odm.manufacturer=unknown\\nro.product.odm.name=unknown\\nro.product.system_ext.name=unknown\\nro.product.odm.device=unknown\\nro.product.system_ext.device=unknown\\n\\n# S9 Ghost - GSM & Baseband Placeholders\\ngsm.version.baseband=unknown\\ngsm.operator.alpha=unknown\\ngsm.sim.operator.alpha=unknown\\ngsm.operator.numeric=unknown\\ngsm.sim.operator.numeric=unknown\\ngsm.sim.gsmoperator.numeric=unknown\\ngsm.operator.iso-country=unknown\\ngsm.sim.operator.iso-country=unknown\\npersist.sys.country=unknown\\npersist.sys.language=unknown\\n' >> \"$bp\"; ");
  sb.append("fi; ");
  ```
* **Đóng gói nhị phân:** Đã biên dịch lại `RecoveryHelper.java` bằng OpenJDK 11 và cập nhật vào `D:\ROM\pchanger\Pchanger-4.4.jar`.

#### 3. Cơ chế bảo vệ thuộc tính vô tuyến Anti-RILD Overwrite kép
* **Tầng 1: Lắng nghe sự kiện Init Trigger (`/system/etc/init/init.fix_storage.rc`):**
  Mỗi khi tiến trình RILD cố tình ghi đè thuộc tính radio, Android `init` sẽ ngay lập tức bắt sự kiện và gọi lệnh nạp lại cấu hình Kernel Ghost:
  ```rc
  on property:ril.product_code=*
      write /proc/s9_serial reload

  on property:ril.sw_ver=*
      write /proc/s9_serial reload

  on property:vendor.ril.product_code=*
      write /proc/s9_serial reload

  on property:vendor.ril.sw_ver=*
      write /proc/s9_serial reload
  ```
* **Tầng 2: Vòng lặp Watchdog nền (`fastboot_seed.sh --boot-completed`):**
  Chạy một tiến trình con nền kiểm tra định kỳ tại các mốc thời gian sau khởi động (5s, 10s, 15s, 20s, 30s, 45s, 60s, 90s) để tái kích hoạt `echo reload > /proc/s9_serial` và đảm bảo các cờ phím điều hướng luôn ở trạng thái kích hoạt:
  ```sh
  (
      for t in 5 10 15 20 30 45 60 90; do
          sleep $t
          settings put global device_provisioned 1 2>/dev/null
          settings put secure user_setup_complete 1 2>/dev/null
          settings put secure sec_setupwizard_complete 1 2>/dev/null
          settings put secure tv_user_setup_complete 1 2>/dev/null
          settings put global adb_enabled 0 2>/dev/null
          settings put global development_settings_enabled 0 2>/dev/null
          if [ -f /proc/s9_serial ]; then
              echo reload > /proc/s9_serial 2>/dev/null
          fi
      done
  ) &
  ```

---

### 7.3. Kết quả kiểm chứng thực nghiệm & Bảng đối chiếu thuộc tính

1. **Thanh điều hướng 3 phím (Navigation Bar):**
   * Hiển thị đầy đủ cả 3 nút: Recents (`|||`), Home (`O`), và Back (`<`) ở thanh đáy màn hình chính (chứng thực qua ảnh chụp màn hình thực tế `home_navbar_3buttons.png`).
   * Không còn hiện tượng chỉ xuất hiện 1 phím Back ở góc đáy trái.

2. **Bảng đối chiếu thuộc tính hệ thống (`getprop`) sau khi nạp bản vá:**

| STT | Thuộc tính (Property Key) | Trạng thái trước vá | Kết quả thực tế sau vá (`getprop`) | Đánh giá |
|:---:|:---|:---|:---|:---:|
| 1 | `ro.product.model` | `SM-N960F` | `SM-N960F` | Khớp 100% |
| 2 | `ro.product.system.model` | `SM-N960F` | `SM-N960F` | Khớp 100% |
| 3 | `ro.product.vendor.model` | `SM-N960F` | `SM-N960F` | Khớp 100% |
| 4 | `ro.product.odm.model` | Không có | `SM-N960F` | Khớp 100% |
| 5 | `ro.product.system_ext.model`| Không có | `SM-N960F` | Khớp 100% |
| 6 | `ro.odm.build.fingerprint` | Không có | `samsung/crownltexx/crownlte:10/...` | Khớp 100% |
| 7 | `ro.system_ext.build.fingerprint` | Không có | `samsung/crownltexx/crownlte:10/...` | Khớp 100% |
| 8 | `ril.product_code` | Bị RILD đè `SM-G960NZRAXXV` | `SM-N960FZRAXXV` | Chống đè thành công |
| 9 | `ril.sw_ver` | Bị RILD đè `G960NKOU5FVA1` | `N960FKOU5FVA1` | Chống đè thành công |
| 10 | `vendor.ril.product_code` | `SM-G960NZRAXXV` | `SM-N960FZRAXXV` | Khớp 100% |
| 11 | `gsm.version.baseband` | Không có | `N960FKOU5FVA1` | Khớp 100% |
| 12 | `gsm.sim.operator.alpha` | Không có | `Viettel` | Khớp 100% |
| 13 | `gsm.operator.numeric` | Không có | `45204` | Khớp 100% |
| 14 | `gsm.operator.iso-country` | Không có | `vn` | Khớp 100% |
| 15 | `persist.sys.country` | Không có | `VN` | Khớp 100% |
| 16 | `persist.sys.language` | Không có | `vi` | Khớp 100% |
| 17 | `ro.pchanger.android` | `""` (Ẩn trắng) | `""` (Ẩn trắng) | Stealth chuẩn |
| 18 | `Pchanger Key Fallback` | `89cb2abb18affe1` | `89cb2abb18affe1` | Tự động nhận diện |
