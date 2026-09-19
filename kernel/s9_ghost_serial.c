/*
 * Samsung Galaxy S9 (SM-G960F / starlte)
 * 100% Kernel-Space Serial Number Virtualization & Identity Cloaking
 *
 * Provides pure in-memory virtualization for:
 * - androidboot.serialno, ap_serial, em_did in /proc/cmdline & bootargs
 * - /proc/device-tree/chosen/bootargs & devicetree sysfs (via of_node_property_read)
 * - Knox Warranty & AVB state: warranty_bit=0, snapQB=OFFICIAL, wb.hs=0000,
 *   sec_debug.bin=O, odin_download=0, verifiedbootstate=green, flash.locked=1
 * - Silicon Exynos ChipID (unique_id, lot_id, lot_id2, SVC_AP, sec_hw_param)
 * - USB Gadget iSerialNumber descriptor (PC host ADB)
 * - /efs/FactoryApp/serial_no in-flight VFS cloaking (Zero EFS disk mutation)
 * - Live Android property memory sync (/dev/__properties__)
 * - Dynamic config file support (/data/adb/ghost.conf or /efs/ghost.conf)
 */

#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/types.h>
#include <linux/string.h>
#include <linux/slab.h>
#include <linux/fs.h>
#include <linux/uaccess.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/dcache.h>
#include <linux/namei.h>
#include <linux/random.h>
#include <linux/ctype.h>
#include <linux/smp.h>
#include <linux/spinlock.h>
#include <linux/workqueue.h>
#include <linux/soc/samsung/exynos-soc.h>
#include <linux/s9_ghost_serial.h>

#define S9_PROP_AREA_SIZE   131072
#define S9_PROP_HEADER_SIZE 128

static struct s9_serial_profile s9_active_serial_prof;
static DEFINE_SPINLOCK(s9_serial_lock);
static struct super_block *s9_efs_sb = NULL;
static struct delayed_work s9_config_reload_work;

static u64 s9_mix64(u64 v, u64 salt)
{
	v ^= salt;
	v *= 0xff51afd7ed558ccdULL;
	v ^= v >> 32;
	v *= 0xc4ceb9fe1a85ec53ULL;
	v ^= v >> 32;
	return v;
}

static u32 s9_chipid_reverse_value(u32 val, u32 bitcnt)
{
	u32 temp, ret = 0;
	u32 i;

	for (i = 0; i < bitcnt; i++) {
		temp = (val >> i) & 0x1;
		ret += temp << ((bitcnt - 1) - i);
	}
	return ret;
}

static void s9_chipid_dec_to_36(u32 in, char *p)
{
	u32 mod;
	int i;

	for (i = 4; i >= 1; i--) {
		mod = in % 36;
		in /= 36;
		p[i] = (mod < 10) ? (mod + '0') : (mod - 10 + 'A');
	}
	p[0] = 'A';
	p[5] = '\0';
}

static void s9_derive_chipid_from_ap(struct s9_serial_profile *p, u64 ap_val)
{
	/* Silicon Unique ID: 0x2323 prefix + 12-hex ap_val */
	p->unique_id = 0x2323000000000000ULL | (ap_val & 0x0FFFFFFFFFFFULL);

	/* Lot ID: unique_id & 0x1FFFFF */
	p->lot_id = (u32)(p->unique_id & 0x1FFFFFULL);

	/* Lot ID2: Samsung Wafer math */
	{
		u32 temp = (u32)(p->unique_id & 0xFFFFFFFF);
		temp = s9_chipid_reverse_value(temp, 32);
		temp = (temp >> 11) & 0x1FFFFF;
		s9_chipid_dec_to_36(temp, p->lot_id2);
	}
}

static void s9_generate_deterministic_profile(struct s9_serial_profile *p)
{
	static const char base34_chars[] = "0123456789ABCDEFGHJKLMNPQRSTUVWXYZ";
	static const char hex_chars[] = "0123456789abcdef";
	u64 seed1, seed2, ap_val;
	char ap_hex[13];
	int i;

	/* High entropy deterministic seed: Salt combined with fixed S9 pepper */
	seed1 = s9_mix64(0x9810533947484F53ULL, 0x5A8EULL);
	seed2 = s9_mix64(seed1, 0x1CD7ULL);

	/* 1. 16-hex serial number (matches S9 cmdline length 16) */
	for (i = 0; i < 16; i++) {
		u8 nibble = (u8)((seed1 >> (i * 4)) & 0xF);
		p->serialno[i] = hex_chars[nibble];
	}
	p->serialno[16] = '\0';

	/* 2. 12-hex AP Serial: 0x0... */
	ap_val = (seed2 & 0x0000FFFFFFFFFFFFULL);
	/* Force top nibble 0 to match S9 standard 0x0AB4... format */
	ap_val &= 0x0FFFFFFFFFFFULL;
	snprintf(ap_hex, sizeof(ap_hex), "%012llX", (unsigned long long)ap_val);

	snprintf(p->ap_serial, sizeof(p->ap_serial), "0x%s", ap_hex);

	/* 3. EM DID: 20 + lowercase ap_hex + 11 */
	p->em_did[0] = '2';
	p->em_did[1] = '0';
	for (i = 0; i < 12; i++)
		p->em_did[2 + i] = tolower(ap_hex[i]);
	p->em_did[14] = '1';
	p->em_did[15] = '1';
	p->em_did[16] = '\0';

	/* 4, 5, 6. Silicon Unique ID, Lot ID, Lot ID2 */
	s9_derive_chipid_from_ap(p, ap_val);

	/* 7. Samsung Factory Serial: R39K + 6 chars */
	p->samsung_serial[0] = 'R';
	p->samsung_serial[1] = '3';
	p->samsung_serial[2] = '9';
	p->samsung_serial[3] = 'K';
	for (i = 0; i < 6; i++) {
		u8 idx = (u8)((seed2 >> (i * 5)) % (sizeof(base34_chars) - 1));
		p->samsung_serial[4 + i] = base34_chars[idx];
	}
	p->samsung_serial[10] = '\0';

	/* 8. Full line for /efs/FactoryApp/serial_no */
	snprintf(p->efs_serial_line, sizeof(p->efs_serial_line),
		 "%s,20180517,AGZ0797860\n", p->samsung_serial);

	p->active = true;
}

static void s9_load_config_file(void)
{
	static const char *const conf_paths[] = {
		"/data/adb/ghost.conf",
		"/data/ghost.conf",
		"/efs/ghost.conf",
		NULL
	};
	struct file *filp;
	char *kbuf, *line, *next_line;
	ssize_t bytes;
	int p_idx;

	kbuf = kmalloc(4096, GFP_KERNEL);
	if (!kbuf)
		return;

	for (p_idx = 0; conf_paths[p_idx]; p_idx++) {
		filp = filp_open(conf_paths[p_idx], O_RDONLY, 0);
		if (IS_ERR(filp))
			continue;

		bytes = kernel_read(filp, 0, kbuf, 4095);
		filp_close(filp, NULL);

		if (bytes > 0) {
			unsigned long flags;
			kbuf[bytes] = '\0';
			line = kbuf;

			spin_lock_irqsave(&s9_serial_lock, flags);
			while (line && *line) {
				char *eq;
				next_line = strchr(line, '\n');
				if (next_line) {
					*next_line = '\0';
					next_line++;
				}

				while (*line == ' ' || *line == '\t')
					line++;
				if (*line == '#' || *line == ';' || *line == '\0') {
					line = next_line;
					continue;
				}

				eq = strchr(line, '=');
				if (eq) {
					char *key = line;
					char *val = eq + 1;
					*eq = '\0';

					while (eq > key && (*(eq - 1) == ' ' || *(eq - 1) == '\t'))
						*(--eq) = '\0';
					while (*val == ' ' || *val == '\t')
						val++;
					{
						char *v_end = val + strlen(val);
						while (v_end > val && (*(v_end - 1) == ' ' || *(v_end - 1) == '\t' ||
								       *(v_end - 1) == '\r'))
							*(--v_end) = '\0';
					}

					if ((!strcasecmp(key, "serialno") || !strcasecmp(key, "serial_no")) && strlen(val) >= 8) {
						strlcpy(s9_active_serial_prof.serialno, val, sizeof(s9_active_serial_prof.serialno));
					} else if (!strcasecmp(key, "ap_serial") && strlen(val) >= 10) {
						u64 num = 0;
						const char *hex_str = val;
						if (hex_str[0] == '0' && (hex_str[1] == 'x' || hex_str[1] == 'X'))
							hex_str += 2;
						if (!kstrtoull(hex_str, 16, &num)) {
							strlcpy(s9_active_serial_prof.ap_serial, val, sizeof(s9_active_serial_prof.ap_serial));
							s9_derive_chipid_from_ap(&s9_active_serial_prof, num);
							/* Synchronize with exynos_soc_info */
							exynos_soc_info.unique_id = s9_active_serial_prof.unique_id;
							exynos_soc_info.lot_id = s9_active_serial_prof.lot_id;
							strlcpy(exynos_soc_info.lot_id2, s9_active_serial_prof.lot_id2, 6);
						}
					} else if (!strcasecmp(key, "em_did") && strlen(val) >= 14) {
						strlcpy(s9_active_serial_prof.em_did, val, sizeof(s9_active_serial_prof.em_did));
					} else if (!strcasecmp(key, "samsung_serial") && strlen(val) >= 8) {
						strlcpy(s9_active_serial_prof.samsung_serial, val, sizeof(s9_active_serial_prof.samsung_serial));
						snprintf(s9_active_serial_prof.efs_serial_line, sizeof(s9_active_serial_prof.efs_serial_line),
							 "%s,20180517,AGZ0797860\n", s9_active_serial_prof.samsung_serial);
					}
				}
				line = next_line;
			}
			spin_unlock_irqrestore(&s9_serial_lock, flags);

			pr_info("S9GhostSerial: Loaded custom profile from %s\n", conf_paths[p_idx]);
			break;
		}
	}

	kfree(kbuf);
}

void s9_ghost_serial_init(void)
{
	unsigned long flags;

	spin_lock_irqsave(&s9_serial_lock, flags);
	if (!s9_active_serial_prof.active) {
		s9_generate_deterministic_profile(&s9_active_serial_prof);
		pr_info("S9GhostSerial: Initialized active profile: serialno=%s ap=%s did=%s lot2=%s\n",
			s9_active_serial_prof.serialno,
			s9_active_serial_prof.ap_serial,
			s9_active_serial_prof.em_did,
			s9_active_serial_prof.lot_id2);
	}
	spin_unlock_irqrestore(&s9_serial_lock, flags);
}

static void s9_ensure_init(void)
{
	if (unlikely(!s9_active_serial_prof.active))
		s9_ghost_serial_init();
}

static void s9_replace_token_value(char *buf, size_t capacity, const char *prefix, const char *new_val)
{
	size_t pfx_len = strlen(prefix);
	size_t val_len = strlen(new_val);
	char *pos = buf;

	if (!buf || capacity == 0 || !prefix || !new_val)
		return;

	while ((pos = strstr(pos, prefix)) != NULL) {
		char *val_start = pos + pfx_len;
		char *val_end = val_start;
		size_t old_val_len;
		size_t tail_len;

		/* Find end of token: whitespace, null, or separator */
		while (*val_end && *val_end != ' ' && *val_end != '\t' &&
		       *val_end != '\r' && *val_end != '\n')
			val_end++;

		old_val_len = (size_t)(val_end - val_start);
		tail_len = strlen(val_end);

		/* Check if replacement fits within capacity */
		if (strlen(buf) - old_val_len + val_len + 1 <= capacity) {
			if (old_val_len != val_len)
				memmove(val_start + val_len, val_end, tail_len + 1);
			memcpy(val_start, new_val, val_len);
			pos = val_start + val_len;
		} else {
			pos = val_end;
			break;
		}
	}
}

static void s9_sanitize_tokens(char *buf, size_t max_len)
{
	if (!buf || max_len == 0)
		return;

	/* 1. Hardware Identity Cloaking */
	s9_replace_token_value(buf, max_len, "androidboot.serialno=", s9_active_serial_prof.serialno);
	s9_replace_token_value(buf, max_len, "androidboot.ap_serial=", s9_active_serial_prof.ap_serial);
	s9_replace_token_value(buf, max_len, "androidboot.em.did=", s9_active_serial_prof.em_did);

	/* 2. Samsung Knox & Warranty Bits */
	s9_replace_token_value(buf, max_len, "androidboot.warranty_bit=", "0");
	s9_replace_token_value(buf, max_len, "sec_debug.warranty_bit=", "0");
	s9_replace_token_value(buf, max_len, "androidboot.wb.hs=", "0000");
	s9_replace_token_value(buf, max_len, "androidboot.wb.snapQB=", "0");
	s9_replace_token_value(buf, max_len, "sec_debug.bin=", "O");
	s9_replace_token_value(buf, max_len, "androidboot.odin_download=", "0");

	/* 3. SafetyNet, Play Integrity & AVB */
	s9_replace_token_value(buf, max_len, "androidboot.flash.locked=", "1");
	s9_replace_token_value(buf, max_len, "androidboot.verifiedbootstate=", "green");
	s9_replace_token_value(buf, max_len, "androidboot.veritymode=", "enforcing");
	s9_replace_token_value(buf, max_len, "androidboot.vbmeta.device_state=", "locked");
}

void s9_ghost_sanitize_cmdline(char *cmd, size_t max_len)
{
	s9_ensure_init();
	s9_sanitize_tokens(cmd, max_len);
}
EXPORT_SYMBOL(s9_ghost_sanitize_cmdline);

void s9_ghost_sanitize_bootargs_buffer(char *buf, size_t len)
{
	s9_ensure_init();
	s9_sanitize_tokens(buf, len);
}
EXPORT_SYMBOL(s9_ghost_sanitize_bootargs_buffer);

void s9_ghost_sync_chipid(u64 *p_unique_id, u32 *p_lot_id, char *lot_id2)
{
	s9_ensure_init();

	if (p_unique_id)
		*p_unique_id = s9_active_serial_prof.unique_id;
	if (p_lot_id)
		*p_lot_id = s9_active_serial_prof.lot_id;
	if (lot_id2)
		strlcpy(lot_id2, s9_active_serial_prof.lot_id2, 6);

	pr_info("S9GhostSerial: Synced Silicon ChipID: uid=0x%016llX lot=0x%08X lot2=%s\n",
		(unsigned long long)s9_active_serial_prof.unique_id,
		s9_active_serial_prof.lot_id,
		s9_active_serial_prof.lot_id2);
}
EXPORT_SYMBOL(s9_ghost_sync_chipid);

void s9_ghost_get_active_serial(char *out, size_t len)
{
	s9_ensure_init();
	if (!out || len == 0)
		return;
	strlcpy(out, s9_active_serial_prof.serialno, len);
}
EXPORT_SYMBOL(s9_ghost_get_active_serial);

bool s9_ghost_is_cloaked_efs_path(const struct path *path)
{
	const char *dname;
	const char *pname;
	const struct dentry *dentry;
	char buf[128];
	char *pathname;

	if (!path || !path->dentry || !path->dentry->d_name.name)
		return false;

	dentry = path->dentry;
	dname = dentry->d_name.name;
	pname = dentry->d_parent ? dentry->d_parent->d_name.name : NULL;

	/* 1. Fast name filter */
	if (!dname || strcmp(dname, "serial_no"))
		return false;
	if (!pname || strcmp(pname, "FactoryApp"))
		return false;

	/* 2. Resolve mount path if needed */
	pathname = d_path(path, buf, sizeof(buf));
	if (IS_ERR(pathname))
		return false;

	if (!strncmp(pathname, "/mnt/vendor/efs/", 16) ||
	    !strncmp(pathname, "/efs/", 5)) {
		if (path->dentry->d_sb && !READ_ONCE(s9_efs_sb))
			WRITE_ONCE(s9_efs_sb, path->dentry->d_sb);
		return true;
	}

	return false;
}
EXPORT_SYMBOL(s9_ghost_is_cloaked_efs_path);

bool s9_ghost_get_cloaked_efs_payload(const char *dname, const char *pname,
				      char *out, size_t out_len, size_t *out_plen)
{
	s9_ensure_init();

	if (!dname || !pname || !out || out_len < 16 || !out_plen)
		return false;

	if (!strcmp(pname, "FactoryApp") && !strcmp(dname, "serial_no")) {
		size_t slen = strlen(s9_active_serial_prof.efs_serial_line);
		if (slen >= out_len)
			return false;
		strlcpy(out, s9_active_serial_prof.efs_serial_line, out_len);
		*out_plen = slen;
		return true;
	}

	return false;
}
EXPORT_SYMBOL(s9_ghost_get_cloaked_efs_payload);

ssize_t s9_ghost_vfs_inject_string(char __user *buf, size_t count, loff_t *pos,
				   const char *src, size_t src_len)
{
	size_t available, to_copy;

	if (!buf || !pos || !src || *pos < 0)
		return -EINVAL;

	if (*pos >= src_len)
		return 0; /* EOF */

	available = src_len - *pos;
	to_copy = min(count, available);

	if (copy_to_user(buf, src + *pos, to_copy))
		return -EFAULT;

	*pos += to_copy;
	return to_copy;
}
EXPORT_SYMBOL(s9_ghost_vfs_inject_string);

/*
 * Memory-Mapped Android Property Live Sync
 */
static int s9_patch_prop_file_one(const char *rel_path, const char *prop_name,
				  const char *new_val, size_t val_len)
{
	struct file *filp;
	char *buf;
	ssize_t bytes;
	int i;
	int patched = 0;
	char full_path[128];

	snprintf(full_path, sizeof(full_path), "/dev/__properties__/%s", rel_path);
	filp = filp_open(full_path, O_RDWR, 0);
	if (IS_ERR(filp))
		return PTR_ERR(filp);

	buf = kmalloc(S9_PROP_AREA_SIZE, GFP_KERNEL);
	if (!buf) {
		filp_close(filp, NULL);
		return -ENOMEM;
	}

	bytes = kernel_read(filp, 0, buf, S9_PROP_AREA_SIZE);
	if (bytes >= (ssize_t)(S9_PROP_HEADER_SIZE + 96 + val_len)) {
		for (i = S9_PROP_HEADER_SIZE; i + 96 + val_len < bytes; i += 4) {
			const char *pname = buf + i + 96;
			if (!strcmp(pname, prop_name)) {
				u32 serial_word;
				u32 dirty_word;
				u32 done_word;
				char clean_val[92];

				memcpy(&serial_word, buf + i, 4);

				/* Step 1: Mark dirty */
				dirty_word = serial_word | 1u;
				kernel_write(filp, &dirty_word, 4, i);
				smp_wmb();

				/* Step 2: Write new value (zero-padded) */
				memset(clean_val, 0, sizeof(clean_val));
				memcpy(clean_val, new_val, min_t(size_t, val_len, sizeof(clean_val) - 1));
				kernel_write(filp, clean_val, sizeof(clean_val), i + 4);
				smp_wmb();

				/* Step 3: Clear dirty and increment version */
				done_word = ((u32)val_len << 24) | (((serial_word | 1u) + 1u) & 0xFFFFFFu);
				kernel_write(filp, &done_word, 4, i);
				patched++;
				break;
			}
		}
	}

	kfree(buf);
	filp_close(filp, NULL);
	return patched;
}

int s9_ghost_patch_properties(void)
{
	s9_ensure_init();

	/* Patch ro.serialno and ro.boot.serialno */
	s9_patch_prop_file_one("u:object_r:serialno_prop:s0", "ro.serialno",
			       s9_active_serial_prof.serialno, strlen(s9_active_serial_prof.serialno));
	s9_patch_prop_file_one("u:object_r:serialno_prop:s0", "ro.boot.serialno",
			       s9_active_serial_prof.serialno, strlen(s9_active_serial_prof.serialno));

	/* Patch ro.boot.ap_serial and ro.boot.em.did */
	s9_patch_prop_file_one("u:object_r:bootloader_prop:s0", "ro.boot.ap_serial",
			       s9_active_serial_prof.ap_serial, strlen(s9_active_serial_prof.ap_serial));
	s9_patch_prop_file_one("u:object_r:bootloader_prop:s0", "ro.boot.em.did",
			       s9_active_serial_prof.em_did, strlen(s9_active_serial_prof.em_did));

	/* Patch boot flags */
	s9_patch_prop_file_one("u:object_r:bootloader_prop:s0", "ro.boot.warranty_bit", "0", 1);
	s9_patch_prop_file_one("u:object_r:bootloader_prop:s0", "ro.boot.wb.hs", "0000", 4);
	s9_patch_prop_file_one("u:object_r:bootloader_prop:s0", "ro.boot.wb.snapQB", "0", 1);
	s9_patch_prop_file_one("u:object_r:bootloader_prop:s0", "ro.boot.odin_download", "0", 1);
	s9_patch_prop_file_one("u:object_r:bootloader_prop:s0", "ro.boot.verifiedbootstate", "green", 5);
	s9_patch_prop_file_one("u:object_r:bootloader_prop:s0", "ro.boot.flash.locked", "1", 1);
	s9_patch_prop_file_one("u:object_r:bootloader_prop:s0", "ro.boot.selinux", "enforcing", 9);
	s9_patch_prop_file_one("u:object_r:default_prop:s0", "ro.build.selinux", "1", 1);

	/* Patch crypto state & type (Build #20) */
	s9_patch_prop_file_one("u:object_r:vold_status_prop:s0", "ro.crypto.state", "encrypted", 9);
	s9_patch_prop_file_one("u:object_r:vold_status_prop:s0", "ro.crypto.type", "file", 4);
	s9_patch_prop_file_one("u:object_r:vold_prop:s0", "ro.crypto.state", "encrypted", 9);
	s9_patch_prop_file_one("u:object_r:vold_prop:s0", "ro.crypto.type", "file", 4);
	s9_patch_prop_file_one("u:object_r:default_prop:s0", "ro.crypto.state", "encrypted", 9);
	s9_patch_prop_file_one("u:object_r:default_prop:s0", "ro.crypto.type", "file", 4);

	/* Always lock ro.build.version.sdk to target SDK (29 on A10, 33 on A13) */
	s9_patch_prop_file_one("u:object_r:build_prop:s0", "ro.build.version.sdk", S9_TARGET_SDK_STR, 2);
	s9_patch_prop_file_one("u:object_r:default_prop:s0", "ro.build.version.sdk", S9_TARGET_SDK_STR, 2);
	s9_patch_prop_file_one("u:object_r:system_prop:s0", "ro.build.version.sdk", S9_TARGET_SDK_STR, 2);

	return 0;
}
EXPORT_SYMBOL(s9_ghost_patch_properties);

static void s9_config_reload_work_fn(struct work_struct *work)
{
	static int passes = 0;
	s9_load_config_file();
	s9_ghost_patch_properties();
	passes++;
	if (passes == 1) {
		schedule_delayed_work(&s9_config_reload_work, msecs_to_jiffies(8000));
	}
}

/*
 * Procfs inspection and control node: /proc/s9_serial
 */
static int s9_serial_proc_show(struct seq_file *m, void *v)
{
	s9_ensure_init();

	seq_puts(m, "=== S9 Ghost Serial Virtualization ===\n");
	seq_printf(m, "Status            : %s\n", s9_active_serial_prof.active ? "ACTIVE" : "INACTIVE");
	seq_puts(m, "SELinux State     : Enforcing (Ghost Cloaked)\n");
	seq_printf(m, "Active SerialNo   : %s\n", s9_active_serial_prof.serialno);
	seq_printf(m, "Active AP Serial  : %s\n", s9_active_serial_prof.ap_serial);
	seq_printf(m, "Active EM DID     : %s\n", s9_active_serial_prof.em_did);
	seq_printf(m, "Active Unique ID  : 0x%016llX\n", (unsigned long long)s9_active_serial_prof.unique_id);
	seq_printf(m, "Active Lot ID     : 0x%08X\n", s9_active_serial_prof.lot_id);
	seq_printf(m, "Active Lot ID2    : %s\n", s9_active_serial_prof.lot_id2);
	seq_printf(m, "Samsung Serial    : %s\n", s9_active_serial_prof.samsung_serial);
	seq_printf(m, "EFS Factory Line  : %s", s9_active_serial_prof.efs_serial_line);
	return 0;
}

static int s9_serial_proc_open(struct inode *inode, struct file *file)
{
	return single_open(file, s9_serial_proc_show, NULL);
}

static ssize_t s9_serial_proc_write(struct file *file, const char __user *buf,
				    size_t count, loff_t *pos)
{
	char kcmd[32];
	size_t len = min(count, sizeof(kcmd) - 1);

	if (copy_from_user(kcmd, buf, len))
		return -EFAULT;
	kcmd[len] = '\0';

	if (strstr(kcmd, "reload") || strstr(kcmd, "sync") || strstr(kcmd, "1")) {
		s9_load_config_file();
		s9_ghost_patch_properties();
		pr_info("S9GhostSerial: Manual reload & property patch triggered via /proc/s9_serial\n");
	}

	return count;
}

static const struct file_operations s9_serial_proc_fops = {
	.open    = s9_serial_proc_open,
	.read    = seq_read,
	.write   = s9_serial_proc_write,
	.llseek  = seq_lseek,
	.release = single_release,
};

static int __init s9_ghost_serial_late_init(void)
{
	s9_ensure_init();
	proc_create("s9_serial", 0644, NULL, &s9_serial_proc_fops);

	INIT_DELAYED_WORK(&s9_config_reload_work, s9_config_reload_work_fn);
	/* Initial property sync at 2 seconds, followed by second pass at 10 seconds */
	schedule_delayed_work(&s9_config_reload_work, msecs_to_jiffies(2000));
	return 0;
}
late_initcall(s9_ghost_serial_late_init);

static int __init s9_ghost_serial_core_init(void)
{
	s9_ghost_serial_init();
	return 0;
}
core_initcall(s9_ghost_serial_core_init);

MODULE_DESCRIPTION("Samsung Galaxy S9 Pure Kernel Serial Number Virtualizer");
MODULE_AUTHOR("khiconjk");
MODULE_LICENSE("GPL v2");
