/*
 * Samsung Galaxy S9 (SM-G960F / SM-G960N / starlte)
 * 100% Kernel-Space Serial Number & Device Profile Virtualization Engine
 *
 * Provides pure in-memory virtualization for:
 * - Dynamic Profile Ingestion: reads 58 fields from /efs/ghost.conf at boot
 * - Live Android property memory sync (/dev/__properties__ across all contexts)
 * - Hardware Identifiers: serialno, ap_serial, em_did in /proc/cmdline & bootargs
 * - Silicon Exynos ChipID (unique_id, lot_id, lot_id2, SVC_AP, sec_hw_param)
 * - Knox Warranty & AVB state: warranty_bit=0, snapQB=0, wb.hs=0000,
 *   sec_debug.bin=O, odin_download=0, verifiedbootstate=green, flash.locked=1
 * - VFS Cloaking: /efs/FactoryApp (serial_no, ap_serial, em_did, samsung_serial, imei, imsi, meid)
 * - VFS Cloaking: /efs/imei/imei.dat, /efs/wifi/.mac.info, /efs/bluetooth/bt_addr
 * - Wi-Fi Driver MAC Cloaking: direct hardware spoofing via bcmdhd
 * - Non-Root / VANILLA clean execution with Zero EFS disk mutation
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
#include <linux/timekeeping.h>
#include <linux/rtc.h>
#include <linux/soc/samsung/exynos-soc.h>
#include <linux/etherdevice.h>
#include <linux/s9_boot_guard.h>
#include <linux/ghost_uptime.h>
#include <linux/s9_ghost_serial.h>

#define S9_PROP_AREA_SIZE   131072
#define S9_PROP_HEADER_SIZE 128
#define S9_MAX_GHOST_PROPS  256
#define S9_PROP_KEY_LEN     64
#define S9_PROP_VAL_LEN     128

struct s9_ghost_prop {
	char key[S9_PROP_KEY_LEN];
	char val[S9_PROP_VAL_LEN];
};

static struct s9_serial_profile s9_active_serial_prof;
static struct s9_ghost_prop s9_ghost_props[S9_MAX_GHOST_PROPS];
static int s9_ghost_prop_count = 0;
static DEFINE_SPINLOCK(s9_serial_lock);
static struct super_block *s9_efs_sb = NULL;
static struct delayed_work s9_config_reload_work;
static bool s9_allow_crypto_cloak = false;
static bool s9_work_initialized = false;

static const char *const s9_prop_contexts[] = {
	"u:object_r:default_prop:s0",
	"u:object_r:build_prop:s0",
	"u:object_r:system_prop:s0",
	"u:object_r:system_product_prop:s0",
	"u:object_r:vendor_prop:s0",
	"u:object_r:odm_prop:s0",
	"u:object_r:telephony_prop:s0",
	"u:object_r:radio_prop:s0",
	"u:object_r:exported_radio_prop:s0",
	"u:object_r:exported_system_prop:s0",
	"u:object_r:exported_default_prop:s0",
	"u:object_r:exported2_default_prop:s0",
	"u:object_r:exported3_default_prop:s0",
	"u:object_r:serialno_prop:s0",
	"u:object_r:ril_serialno_prop:s0",
	"u:object_r:security_prop:s0",
	"u:object_r:dynamic_system_prop:s0",
	"u:object_r:vendor_default_prop:s0",
	"u:object_r:vendor_radio_prop:s0",
	"u:object_r:system_radio_prop:s0",
	"u:object_r:vendor_rild_prop:s0",
	"u:object_r:exported_config_prop:s0",
	"u:object_r:odsign_prop:s0",
	"u:object_r:vold_prop:s0",
	"u:object_r:vold_status_prop:s0",
	"u:object_r:setupwizard_prop:s0",
	"u:object_r:fingerprint_prop:s0",
	"u:object_r:bluetooth_prop:s0",
	"u:object_r:sec_bluetooth_prop:s0",
	"u:object_r:wifi_prop:s0",
	"u:object_r:exported_wifi_prop:s0",
	"u:object_r:wifi_log_prop:s0",
	"u:object_r:audio_prop:s0",
	"u:object_r:bootloader_boot_reason_prop:s0",
	"u:object_r:system_boot_reason_prop:s0",
	"u:object_r:last_boot_reason_prop:s0",
	"u:object_r:debug_prop:s0",
	NULL
};

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

	/* 8. Dynamic RIL Barcode & Factory Dates */
	snprintf(p->ril_barcode, sizeof(p->ril_barcode), "AGZ%07u", (u32)(seed2 % 10000000ULL));
	snprintf(p->ril_mfg_date, sizeof(p->ril_mfg_date), "20180517");
	snprintf(p->ril_rfcal_date, sizeof(p->ril_rfcal_date), "20180521");
	snprintf(p->efs_serial_line, sizeof(p->efs_serial_line),
		 "%s,%s,%s\n", p->samsung_serial, p->ril_mfg_date, p->ril_barcode);

	/* 9. Default Dynamic Widevine DRM ID */
	{
		static const char hex_chars[] = "0123456789abcdef";
		u64 drm_seed = seed2;
		for (i = 0; i < 32; i++) {
			drm_seed = s9_mix64(drm_seed, 0x517cc1b727220a95ULL + i);
			p->drm_id_bytes[i] = (u8)(drm_seed & 0xFF);
			p->drm_id_hex[i * 2] = hex_chars[(p->drm_id_bytes[i] >> 4) & 0xF];
			p->drm_id_hex[i * 2 + 1] = hex_chars[p->drm_id_bytes[i] & 0xF];
		}
		p->drm_id_hex[64] = '\0';
		p->has_drm_id = true;
	}

	/* 10. Default Dynamic eMMC & UFS Storage Identifiers */
	{
		u32 psn = (u32)(seed2 & 0xFFFFFFFF);
		u32 ufs_rand = (u32)((seed1 >> 16) & 0xFFFFF);

		/* eMMC CID (Samsung JEDEC format: MID 0x15, CBX 0x01, OEM 0x00, DJ4U1E, PRV 0x08, PSN, MDT 0x026, CRC 0x01 = 32 hex chars) */
		snprintf(p->emmc_cid, sizeof(p->emmc_cid),
			 "150100444A3455314508%08X0261", psn);
		p->has_emmc_cid = true;

		snprintf(p->emmc_serial, sizeof(p->emmc_serial), "0x%08x\n", psn);
		strlcpy(p->emmc_name, "DJ4U1E\n", sizeof(p->emmc_name));
		strlcpy(p->emmc_manfid, "0x000015\n", sizeof(p->emmc_manfid));
		strlcpy(p->emmc_oemid, "0x0100\n", sizeof(p->emmc_oemid));
		strlcpy(p->emmc_date, "09/2020\n", sizeof(p->emmc_date));

		/* UFS Serial & VPD Page 0x80 (12 bytes: 00 80 00 08 'F' 'D' c0 c1 c2 c3 c4 00) */
		snprintf(p->ufs_serial, sizeof(p->ufs_serial), "FD%05X\n", ufs_rand);
		p->ufs_vpd_pg80[0] = 0x00;
		p->ufs_vpd_pg80[1] = 0x80;
		p->ufs_vpd_pg80[2] = 0x00;
		p->ufs_vpd_pg80[3] = 0x08;
		p->ufs_vpd_pg80[4] = 'F';
		p->ufs_vpd_pg80[5] = 'D';
		snprintf((char *)&p->ufs_vpd_pg80[6], 6, "%05X", ufs_rand);
		p->ufs_vpd_pg80[11] = '\0';
		p->ufs_vpd_pg80_len = 12;

		/* UFS WWID */
		snprintf(p->ufs_wwid, sizeof(p->ufs_wwid), "eui.53414d53554e47%02X\n", (u8)(seed2 >> 32));
		p->has_ufs_wwid = true;
	}

	/* 11. Realistic Deterministic Uptime Profile: 12 hours (43,200s) to 4.5 days (388,800s) */
	{
		u64 uptime_seed = s9_mix64(seed1 ^ (seed2 >> 11), 0x555054494D45ULL);
		u64 prof_uptime_sec = 43200ULL + (uptime_seed % 345601ULL);
		s9_ghost_uptime_set_offset_sec(prof_uptime_sec);
	}

	p->active = true;
}

static void s9_ghost_set_prop(const char *key, const char *val)
{
	int i;
	if (!key || !*key || !val)
		return;

	/* Never allow debuggable=1 to leak */
	if (!strcmp(key, "ro.debuggable"))
		val = "0";

	for (i = 0; i < s9_ghost_prop_count; i++) {
		if (!strcmp(s9_ghost_props[i].key, key)) {
			strlcpy(s9_ghost_props[i].val, val, sizeof(s9_ghost_props[i].val));
			return;
		}
	}

	if (s9_ghost_prop_count < S9_MAX_GHOST_PROPS) {
		strlcpy(s9_ghost_props[s9_ghost_prop_count].key, key, sizeof(s9_ghost_props[s9_ghost_prop_count].key));
		strlcpy(s9_ghost_props[s9_ghost_prop_count].val, val, sizeof(s9_ghost_props[s9_ghost_prop_count].val));
		s9_ghost_prop_count++;
	}
}

static const char *s9_ghost_get_prop(const char *key)
{
	int i;
	if (!key || !*key)
		return NULL;
	for (i = 0; i < s9_ghost_prop_count; i++) {
		if (!strcmp(s9_ghost_props[i].key, key))
			return s9_ghost_props[i].val;
	}
	return NULL;
}

static void s9_ghost_harmonize_properties(void)
{
	const char *model = s9_ghost_get_prop("ro.product.model");
	const char *device = s9_ghost_get_prop("ro.product.device");
	const char *name = s9_ghost_get_prop("ro.product.name");
	const char *brand = s9_ghost_get_prop("ro.product.brand");
	const char *mfg = s9_ghost_get_prop("ro.product.manufacturer");
	const char *fp = s9_ghost_get_prop("ro.build.fingerprint");
	const char *inc = s9_ghost_get_prop("ro.build.version.incremental");
	const char *sales_code = s9_ghost_get_prop("ro.csc.sales_code");
	const char *unified_csc = "SKC";
	const char *csc_country = "KOREA";
	const char *csc_iso = "KR";

	/* 1. Model & CSC/OMC harmonization across system, vendor, odm, boot */
	if (model && *model) {
		char selinux_buf[64];
		char prod_code[64];
		char region_props[32];
		char omc_path[64];
		char omc_etcpath[64];
		char omc_respath[64];
		bool is_kr_model = (strstr(model, "960N") || strstr(model, "965N") ||
				    model[strlen(model) - 1] == 'N');

		if (is_kr_model) {
			unified_csc = "SKC";
			csc_country = "KOREA";
			csc_iso = "KR";
		} else {
			if (sales_code && *sales_code &&
			    strcmp(sales_code, "KTC") && strcmp(sales_code, "SKC") &&
			    strcmp(sales_code, "LUC") && strcmp(sales_code, "KOO")) {
				unified_csc = sales_code;
			} else {
				unified_csc = "XXV";
			}
			if (!strcmp(unified_csc, "XXV")) {
				csc_country = "VIETNAM";
				csc_iso = "VN";
			}
		}

		s9_ghost_set_prop("ro.product.system.model", model);
		s9_ghost_set_prop("ro.product.vendor.model", model);
		s9_ghost_set_prop("ro.product.odm.model", model);
		s9_ghost_set_prop("ro.product.system_ext.model", model);
		s9_ghost_set_prop("ro.boot.em.model", model);

		/* SELinux policy version: SEPF_<MODEL>_10_0030 */
		snprintf(selinux_buf, sizeof(selinux_buf), "SEPF_%s_10_0030", model);
		s9_ghost_set_prop("selinux.policy_version", selinux_buf);

		/* Unified CSC / OMC / CarrierID / Product Code */
		s9_ghost_set_prop("ro.csc.sales_code", unified_csc);
		s9_ghost_set_prop("ro.csc.omcnw_code", unified_csc);
		s9_ghost_set_prop("ro.csc.omcnw_code2", unified_csc);
		s9_ghost_set_prop("ro.boot.carrierid", unified_csc);
		s9_ghost_set_prop("persist.audio.sales_code", unified_csc);
		s9_ghost_set_prop("ro.csc.country_code", csc_country);
		s9_ghost_set_prop("ro.csc.countryiso_code", csc_iso);

		snprintf(region_props, sizeof(region_props), "%s.%s", unified_csc, unified_csc);
		s9_ghost_set_prop("ril.region_props", region_props);

		snprintf(prod_code, sizeof(prod_code), "%sZRA%s", model, unified_csc);
		s9_ghost_set_prop("ril.product_code", prod_code);
		s9_ghost_set_prop("vendor.ril.product_code", prod_code);

		snprintf(omc_path, sizeof(omc_path), "/odm/etc/omc/%s/conf", unified_csc);
		snprintf(omc_etcpath, sizeof(omc_etcpath), "/odm/etc/omc/%s/etc", unified_csc);
		snprintf(omc_respath, sizeof(omc_respath), "/odm/etc/omc/%s/res", unified_csc);
		s9_ghost_set_prop("persist.sys.omc_path", omc_path);
		s9_ghost_set_prop("persist.sys.omc_etcpath", omc_etcpath);
		s9_ghost_set_prop("persist.sys.omc_respath", omc_respath);
		s9_ghost_set_prop("persist.sys.omcnw_path", omc_path);
		s9_ghost_set_prop("persist.sys.omcnw_path2", omc_path);
		s9_ghost_set_prop("persist.sys.carrierid_etcpath", omc_etcpath);

		/* Baseband, CSC version & Bluetooth FW version harmonization */
		{
			const char *raw_model = model;
			if (!strncmp(raw_model, "SM-", 3))
				raw_model += 3;
			if (strlen(raw_model) >= 4) {
				char csc_buf[64];
				char bb_buf[64];
				const char *conf_bb = s9_ghost_get_prop("gsm.version.baseband");
				const char *conf_csc = s9_ghost_get_prop("ril.official_cscver");

				if (conf_bb && *conf_bb) {
					strlcpy(bb_buf, conf_bb, sizeof(bb_buf));
				} else if (inc && *inc && strlen(inc) >= 8) {
					strlcpy(bb_buf, inc, sizeof(bb_buf));
					if (strstr(bb_buf, "KSU")) {
						char *ksu = strstr(bb_buf, "KSU");
						ksu[1] = 'O'; /* KOU */
					}
				} else if (strstr(raw_model, "F")) {
					snprintf(bb_buf, sizeof(bb_buf), "%sXXUHFVB4", raw_model);
				} else {
					snprintf(bb_buf, sizeof(bb_buf), "%sKOU3DTC5", raw_model);
				}

				if (conf_csc && *conf_csc) {
					strlcpy(csc_buf, conf_csc, sizeof(csc_buf));
				} else if (inc && *inc && strlen(inc) >= 8) {
					strlcpy(csc_buf, inc, sizeof(csc_buf));
					if (strstr(csc_buf, "KSU")) {
						char *ksu = strstr(csc_buf, "KSU");
						ksu[0] = 'O';
						ksu[1] = 'K';
						ksu[2] = 'R'; /* OKR */
					}
				} else if (strstr(raw_model, "F")) {
					snprintf(csc_buf, sizeof(csc_buf), "%sOXMHFVB4", raw_model);
				} else {
					snprintf(csc_buf, sizeof(csc_buf), "%sOKR3DTC5", raw_model);
				}

				s9_ghost_set_prop("ril.official_cscver", csc_buf);
				s9_ghost_set_prop("ro.omc.build.version", csc_buf);
				s9_ghost_set_prop("gsm.version.baseband", bb_buf);
				s9_ghost_set_prop("ril.sw_ver", bb_buf);
			}
			/* Hardware Match Constraint: Model-specific LCD density & BT FW */
			if (strstr(model, "G965")) {
				s9_ghost_set_prop("ro.sf.lcd_density", "529");
				s9_ghost_set_prop("vendor.bluetooth_fw_ver",
						  "BCM4361B2 Star2 E32A ANT1 [Baseline: 0111]");
			} else {
				s9_ghost_set_prop("ro.sf.lcd_density", "570");
				s9_ghost_set_prop("vendor.bluetooth_fw_ver",
						  "BCM4361B2 Star1 E32A ANT1 [Baseline: 0111]");
			}
		}
	} else {
		s9_ghost_set_prop("vendor.bluetooth_fw_ver",
				  "BCM4361B2 Star1 E32A ANT1 [Baseline: 0111]");
	}

	/* 2. Device & Build Product harmonization across system, vendor, odm */
	if (device && *device) {
		s9_ghost_set_prop("ro.product.system.device", device);
		s9_ghost_set_prop("ro.product.vendor.device", device);
		s9_ghost_set_prop("ro.product.odm.device", device);
		s9_ghost_set_prop("ro.product.system_ext.device", device);
		s9_ghost_set_prop("ro.build.product", device);
	}
	s9_ghost_set_prop("ro.product.board", "universal9810");
	s9_ghost_set_prop("ro.board.platform", "exynos5");
	s9_ghost_set_prop("net.bt.name", "Android");

	/* 3. Name / Product name harmonization */
	if (name && *name) {
		s9_ghost_set_prop("ro.product.system.name", name);
		s9_ghost_set_prop("ro.product.vendor.name", name);
		s9_ghost_set_prop("ro.product.odm.name", name);
		s9_ghost_set_prop("ro.product.system_ext.name", name);
	}

	/* 4. Brand & Manufacturer harmonization */
	if (brand && *brand) {
		s9_ghost_set_prop("ro.product.system.brand", brand);
		s9_ghost_set_prop("ro.product.vendor.brand", brand);
		s9_ghost_set_prop("ro.product.odm.brand", brand);
		s9_ghost_set_prop("ro.product.system_ext.brand", brand);
	}
	if (mfg && *mfg) {
		s9_ghost_set_prop("ro.product.system.manufacturer", mfg);
		s9_ghost_set_prop("ro.product.vendor.manufacturer", mfg);
		s9_ghost_set_prop("ro.product.odm.manufacturer", mfg);
	}

	/* 5. Build Fingerprint harmonization */
	if (fp && *fp) {
		s9_ghost_set_prop("ro.system.build.fingerprint", fp);
		s9_ghost_set_prop("ro.vendor.build.fingerprint", fp);
		s9_ghost_set_prop("ro.bootimage.build.fingerprint", fp);
		s9_ghost_set_prop("ro.odm.build.fingerprint", fp);
		s9_ghost_set_prop("ro.system_ext.build.fingerprint", fp);
	}

	/* 6. Incremental & PDA / Bootloader harmonization */
	if (inc && *inc) {
		s9_ghost_set_prop("ro.system.build.version.incremental", inc);
		s9_ghost_set_prop("ro.vendor.build.version.incremental", inc);
		s9_ghost_set_prop("ro.bootloader", inc);
		s9_ghost_set_prop("ro.boot.bootloader", inc);
		s9_ghost_set_prop("ro.build.PDA", inc);
	}

	/* 6b. Build keys, tags, type, user, host, dates & hardware security flags */
	s9_ghost_set_prop("ro.build.keys", "release-keys");
	s9_ghost_set_prop("ro.build.tags", "release-keys");
	s9_ghost_set_prop("ro.system.build.tags", "release-keys");
	s9_ghost_set_prop("ro.vendor.build.tags", "release-keys");
	s9_ghost_set_prop("ro.bootimage.build.tags", "release-keys");
	s9_ghost_set_prop("ro.odm.build.tags", "release-keys");
	s9_ghost_set_prop("ro.build.type", "user");
	s9_ghost_set_prop("ro.system.build.type", "user");
	s9_ghost_set_prop("ro.vendor.build.type", "user");
	s9_ghost_set_prop("ro.bootimage.build.type", "user");
	s9_ghost_set_prop("ro.odm.build.type", "user");
	s9_ghost_set_prop("ro.build.user", "dpi");
	{
		const char *bhost = s9_ghost_get_prop("ro.build.host");
		if (!bhost || !*bhost || !strcmp(bhost, "crownlte") ||
		    !strcmp(bhost, "crownltexx") || !strcmp(bhost, "starlte") ||
		    !strcmp(bhost, "star2lte")) {
			s9_ghost_set_prop("ro.build.host", "SWDD5915");
		}
	}
	{
		const char *bdate = s9_ghost_get_prop("ro.build.date");
		const char *bdate_utc = s9_ghost_get_prop("ro.build.date.utc");
		if (!bdate || !*bdate || strstr(bdate, "2026"))
			bdate = "Tue Jul 12 18:30:00 KST 2022";
		if (!bdate_utc || !*bdate_utc || !strncmp(bdate_utc, "175", 3) ||
		    !strncmp(bdate_utc, "176", 3) || !strncmp(bdate_utc, "177", 3))
			bdate_utc = "1657618200";
		s9_ghost_set_prop("ro.build.date", bdate);
		s9_ghost_set_prop("ro.system.build.date", bdate);
		s9_ghost_set_prop("ro.vendor.build.date", bdate);
		s9_ghost_set_prop("ro.bootimage.build.date", bdate);
		s9_ghost_set_prop("ro.build.date.utc", bdate_utc);
		s9_ghost_set_prop("ro.system.build.date.utc", bdate_utc);
		s9_ghost_set_prop("ro.vendor.build.date.utc", bdate_utc);
		s9_ghost_set_prop("ro.bootimage.build.date.utc", bdate_utc);
	}
	s9_ghost_set_prop("security.securehw.available", "true");
	s9_ghost_set_prop("security.securenvm.available", "true");

	/* 6c. Block device, OEM Unlock, and Boot Reason harmonization */
	s9_ghost_set_prop("dev.mnt.blk.data", "dm-3");
	s9_ghost_set_prop("ro.oem_unlock_supported", "0");
	s9_ghost_set_prop("sys.oem_unlock_allowed", "0");
	s9_ghost_set_prop("ro.boot.bootreason", "reboot");
	s9_ghost_set_prop("sys.boot.reason", "reboot");
	s9_ghost_set_prop("sys.boot.reason.last", "reboot");
	s9_ghost_set_prop("persist.sys.boot.reason", "");
	s9_ghost_set_prop("persist.sys.boot.reason.history", "reboot");

	/* 7. Hardware Serials unified across ro.serialno, ro.boot.serialno & ril.serialnumber */
	if (s9_active_serial_prof.ap_serial[0])
		s9_ghost_set_prop("ro.boot.ap_serial", s9_active_serial_prof.ap_serial);
	if (s9_active_serial_prof.em_did[0])
		s9_ghost_set_prop("ro.boot.em.did", s9_active_serial_prof.em_did);
	if (s9_active_serial_prof.serialno[0]) {
		strlcpy(s9_active_serial_prof.samsung_serial, s9_active_serial_prof.serialno,
			sizeof(s9_active_serial_prof.samsung_serial));
		snprintf(s9_active_serial_prof.efs_serial_line,
			 sizeof(s9_active_serial_prof.efs_serial_line),
			 "%s,%s,%s\n", s9_active_serial_prof.samsung_serial,
			 s9_active_serial_prof.ril_mfg_date[0] ? s9_active_serial_prof.ril_mfg_date : "20180517",
			 s9_active_serial_prof.ril_barcode[0] ? s9_active_serial_prof.ril_barcode : "AGZ0797860");
		s9_ghost_set_prop("ro.serialno", s9_active_serial_prof.serialno);
		s9_ghost_set_prop("ro.boot.serialno", s9_active_serial_prof.serialno);
		s9_ghost_set_prop("ril.serialnumber", s9_active_serial_prof.serialno);
	}

	/* 7b. Dynamic RIL Barcode, Factory Dates & Widevine DRM ID */
	if (s9_active_serial_prof.ril_barcode[0])
		s9_ghost_set_prop("ril.barcode", s9_active_serial_prof.ril_barcode);
	if (s9_active_serial_prof.ril_mfg_date[0])
		s9_ghost_set_prop("ril.manufacturedate", s9_active_serial_prof.ril_mfg_date);
	if (s9_active_serial_prof.ril_rfcal_date[0])
		s9_ghost_set_prop("ril.rfcal_date", s9_active_serial_prof.ril_rfcal_date);
	if (s9_active_serial_prof.has_drm_id) {
		s9_ghost_set_prop("ro.boot.drm.id", s9_active_serial_prof.drm_id_hex);
		s9_ghost_set_prop("drm_id", s9_active_serial_prof.drm_id_hex);
	}
	s9_ghost_set_prop("ro.debuggable", "0");

	/* 8. Telephony & Carrier harmonization (100% unified MCC/MNC across SIM, RIL & SecOperator) */
	{
		const char *c_name = s9_ghost_get_prop("carrier_provider_name");
		const char *c_code = s9_ghost_get_prop("carrier_provider_code");
		if (!c_name || !*c_name)
			c_name = s9_ghost_get_prop("gsm.sim.operator.alpha");
		if (!c_name || !*c_name)
			c_name = s9_ghost_get_prop("gsm.operator.alpha");
		if (!c_code || !*c_code)
			c_code = s9_ghost_get_prop("gsm.sim.operator.numeric");
		if (!c_code || !*c_code)
			c_code = s9_ghost_get_prop("gsm.operator.numeric");

		if (!c_name || !*c_name || !c_code || !*c_code) {
			s9_ghost_set_prop("gsm.sim.state", "LOADED");
			s9_ghost_set_prop("vendor.gsm.sim.state", "LOADED");
			s9_ghost_set_prop("gsm.network.type", "Unknown");
			s9_ghost_set_prop("vendor.gsm.network.type", "Unknown");
			s9_ghost_set_prop("gsm.voice.network.type", "Unknown");
			s9_ghost_set_prop("gsm.data.network.type", "Unknown");
			s9_ghost_set_prop("gsm.operator.alpha", "");
			s9_ghost_set_prop("gsm.sim.operator.alpha", "");
			s9_ghost_set_prop("gsm.operator.numeric", "");
			s9_ghost_set_prop("gsm.sim.operator.numeric", "");
			s9_ghost_set_prop("gsm.sim.gsmoperator.numeric", "");
			s9_ghost_set_prop("gsm.operator.iso-country", "");
			s9_ghost_set_prop("gsm.sim.operator.iso-country", "");
			s9_ghost_set_prop("gsm.operator.isroaming", "false");
			s9_ghost_set_prop("ril.simoperator", "");
			s9_ghost_set_prop("persist.sys.sec_operator", "");
			s9_ghost_set_prop("ril.rejectedPlmn", "");
			s9_ghost_set_prop("ril.epdg.currenMno", "");
			s9_ghost_set_prop("ril.wfc.default_spn", "");
			s9_ghost_set_prop("gsm.STK_SETUP_MENU", "");
		} else {
			/* Unified In-Service / LTE / Carrier across all telephony properties */
			char epdg_buf[64];
			const char *net_type = s9_ghost_get_prop("gsm.network.type");
			if (!net_type || !*net_type || !strcmp(net_type, "Unknown")) {
				s9_ghost_set_prop("gsm.network.type", "LTE");
				s9_ghost_set_prop("vendor.gsm.network.type", "LTE");
				s9_ghost_set_prop("gsm.voice.network.type", "LTE");
				s9_ghost_set_prop("gsm.data.network.type", "LTE");
			}
			s9_ghost_set_prop("gsm.sim.state", "LOADED");
			s9_ghost_set_prop("vendor.gsm.sim.state", "LOADED");
			s9_ghost_set_prop("gsm.operator.alpha", c_name);
			s9_ghost_set_prop("gsm.sim.operator.alpha", c_name);
			s9_ghost_set_prop("gsm.operator.numeric", c_code);
			s9_ghost_set_prop("gsm.sim.operator.numeric", c_code);
			s9_ghost_set_prop("gsm.sim.gsmoperator.numeric", c_code);
			s9_ghost_set_prop("gsm.operator.isroaming", "false");
			s9_ghost_set_prop("ril.simoperator", c_code);
			s9_ghost_set_prop("persist.sys.sec_operator", c_code);
			s9_ghost_set_prop("ril.rejectedPlmn", "");
			s9_ghost_set_prop("ril.wfc.default_spn", c_name);

			/* Derive ISO Country & Timezone from MCC (e.g. 452 -> vn / Asia/Ho_Chi_Minh) */
			if (!strncmp(c_code, "452", 3)) {
				s9_ghost_set_prop("gsm.operator.iso-country", "vn");
				s9_ghost_set_prop("gsm.sim.operator.iso-country", "vn");
				s9_ghost_set_prop("persist.sys.timezone", "Asia/Ho_Chi_Minh");
			} else if (!strncmp(c_code, "450", 3)) {
				s9_ghost_set_prop("gsm.operator.iso-country", "kr");
				s9_ghost_set_prop("gsm.sim.operator.iso-country", "kr");
			} else if (!strncmp(c_code, "310", 3) || !strncmp(c_code, "311", 3)) {
				s9_ghost_set_prop("gsm.operator.iso-country", "us");
				s9_ghost_set_prop("gsm.sim.operator.iso-country", "us");
			} else {
				const char *iso = s9_ghost_get_prop("ro.csc.countryiso_code");
				if (iso && *iso) {
					char iso_lower[8];
					int j;
					for (j = 0; j < sizeof(iso_lower) - 1 && iso[j]; j++)
						iso_lower[j] = tolower(iso[j]);
					iso_lower[j] = '\0';
					s9_ghost_set_prop("gsm.operator.iso-country", iso_lower);
					s9_ghost_set_prop("gsm.sim.operator.iso-country", iso_lower);
				}
			}

			snprintf(epdg_buf, sizeof(epdg_buf), "%s_VN", c_name);
			s9_ghost_set_prop("ril.epdg.currenMno", epdg_buf);
		}
	}

	/* 9. Router Wi-Fi BSSID, Gateway ARP MAC, SSID & Local IP deterministic derivation */
	{
		static const u8 router_ouis[8][3] = {
			{ 0xc8, 0x3a, 0x35 }, /* Tenda */
			{ 0xdc, 0x71, 0x96 }, /* ZTE / Viettel */
			{ 0xe4, 0x6f, 0x13 }, /* Huawei / VNPT */
			{ 0xa4, 0x2b, 0x8c }, /* TP-Link */
			{ 0x04, 0xd4, 0xc4 }, /* ASUS */
			{ 0x78, 0x44, 0x76 }, /* Totolink */
			{ 0x50, 0xc7, 0xbf }, /* TP-Link */
			{ 0x28, 0xee, 0x52 }, /* TP-Link */
		};
		static const char *const ssid7_prefixes[8] = {
			"VNPT_", "FPT_5", "Home_", "Wifi_",
			"Viet_", "Cafe_", "Link_", "Net5_"
		};
		static const char hex_up[] = "0123456789ABCDEF";
		u64 net_hash = 0x524F555445525339ULL;
		int idx;
		u8 oct;

		for (idx = 0; s9_active_serial_prof.serialno[idx]; idx++) {
			net_hash = s9_mix64(net_hash ^ (u8)s9_active_serial_prof.serialno[idx],
					    0x9E3779B97F4A7C15ULL);
		}

		if (!s9_active_serial_prof.has_wifi_bssid) {
			const u8 *oui = router_ouis[net_hash & 7];
			s9_active_serial_prof.wifi_bssid_bytes[0] = oui[0];
			s9_active_serial_prof.wifi_bssid_bytes[1] = oui[1];
			s9_active_serial_prof.wifi_bssid_bytes[2] = oui[2];
			s9_active_serial_prof.wifi_bssid_bytes[3] = (u8)((net_hash >> 8) & 0xFF);
			s9_active_serial_prof.wifi_bssid_bytes[4] = (u8)((net_hash >> 16) & 0xFF);
			s9_active_serial_prof.wifi_bssid_bytes[5] = (u8)(((net_hash >> 24) & 0xFE) | 0x02);
			snprintf(s9_active_serial_prof.wifi_bssid_str,
				 sizeof(s9_active_serial_prof.wifi_bssid_str),
				 "%02x:%02x:%02x:%02x:%02x:%02x",
				 s9_active_serial_prof.wifi_bssid_bytes[0],
				 s9_active_serial_prof.wifi_bssid_bytes[1],
				 s9_active_serial_prof.wifi_bssid_bytes[2],
				 s9_active_serial_prof.wifi_bssid_bytes[3],
				 s9_active_serial_prof.wifi_bssid_bytes[4],
				 s9_active_serial_prof.wifi_bssid_bytes[5]);
			s9_active_serial_prof.has_wifi_bssid = true;
		}

		/* Gateway LAN ARP MAC shares router OUI + board ID, differs in low bits */
		memcpy(s9_active_serial_prof.wifi_arp_mac_bytes,
		       s9_active_serial_prof.wifi_bssid_bytes, 6);
		s9_active_serial_prof.wifi_arp_mac_bytes[5] ^= 0x03;
		snprintf(s9_active_serial_prof.wifi_arp_mac_str,
			 sizeof(s9_active_serial_prof.wifi_arp_mac_str),
			 "%02x:%02x:%02x:%02x:%02x:%02x",
			 s9_active_serial_prof.wifi_arp_mac_bytes[0],
			 s9_active_serial_prof.wifi_arp_mac_bytes[1],
			 s9_active_serial_prof.wifi_arp_mac_bytes[2],
			 s9_active_serial_prof.wifi_arp_mac_bytes[3],
			 s9_active_serial_prof.wifi_arp_mac_bytes[4],
			 s9_active_serial_prof.wifi_arp_mac_bytes[5]);

		/* 7-char SSID (exact length match for "Thu Tra" in-place Parcel spoofing) */
		snprintf(s9_active_serial_prof.wifi_ssid7_str,
			 sizeof(s9_active_serial_prof.wifi_ssid7_str),
			 "%s%c%c",
			 ssid7_prefixes[(net_hash >> 3) & 7],
			 hex_up[(net_hash >> 12) & 0xF],
			 hex_up[(net_hash >> 20) & 0xF]);
		if (!s9_active_serial_prof.has_wifi_ssid) {
			strlcpy(s9_active_serial_prof.wifi_ssid_str,
				s9_active_serial_prof.wifi_ssid7_str,
				sizeof(s9_active_serial_prof.wifi_ssid_str));
			s9_active_serial_prof.has_wifi_ssid = true;
		}

		/* Deterministic 3-digit IPv4 host octet (101..248, never 183) */
		oct = (u8)(101 + ((net_hash >> 32) % 148));
		if (oct == 183)
			oct = 184;
		s9_active_serial_prof.wifi_ip_octet = oct;
		snprintf(s9_active_serial_prof.wifi_ip_octet_str,
			 sizeof(s9_active_serial_prof.wifi_ip_octet_str),
			 "%03u", (unsigned int)oct);
	}
}

static bool s9_parse_mac_address(const char *str, u8 *bytes)
{
	int values[6];
	int i;

	if (sscanf(str, "%x:%x:%x:%x:%x:%x",
		   &values[0], &values[1], &values[2],
		   &values[3], &values[4], &values[5]) == 6) {
		for (i = 0; i < 6; i++)
			bytes[i] = (u8)values[i];
		return true;
	}
	return false;
}

static void s9_load_config_file(void)
{
	static const char *const conf_paths[] = {
		"/mnt/vendor/efs/ghost.conf",
		"/efs/ghost.conf",
		"/data/adb/ghost.conf",
		"/data/ghost.conf",
		NULL
	};
	struct file *filp;
	char *kbuf, *line, *next_line;
	ssize_t bytes;
	int p_idx;

	kbuf = kmalloc(16384, GFP_KERNEL);
	if (!kbuf)
		return;

	for (p_idx = 0; conf_paths[p_idx]; p_idx++) {
		filp = filp_open(conf_paths[p_idx], O_RDONLY, 0);
		if (IS_ERR(filp))
			continue;

		bytes = kernel_read(filp, 0, kbuf, 16383);
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
					/* Strip surrounding quotes if present */
					if ((val[0] == '"' && val[strlen(val) - 1] == '"') ||
					    (val[0] == '\'' && val[strlen(val) - 1] == '\'')) {
						size_t qlen = strlen(val);
						if (qlen >= 2) {
							val[qlen - 1] = '\0';
							val++;
						}
					}

					/* 1. Hardware & Serial Identifiers */
					if ((!strcasecmp(key, "serialno") || !strcasecmp(key, "serial_no") ||
					     !strcasecmp(key, "efs.serial_no") || !strcasecmp(key, "efs.serialno")) && strlen(val) >= 4) {
						strlcpy(s9_active_serial_prof.serialno, val, sizeof(s9_active_serial_prof.serialno));
						s9_ghost_set_prop("ro.serialno", val);
						s9_ghost_set_prop("ro.boot.serialno", val);
					} else if ((!strcasecmp(key, "ap_serial") || !strcasecmp(key, "efs.ap_serial")) && strlen(val) >= 10) {
						u64 num = 0;
						const char *hex_str = val;
						if (hex_str[0] == '0' && (hex_str[1] == 'x' || hex_str[1] == 'X'))
							hex_str += 2;
						if (!kstrtoull(hex_str, 16, &num)) {
							strlcpy(s9_active_serial_prof.ap_serial, val, sizeof(s9_active_serial_prof.ap_serial));
							s9_derive_chipid_from_ap(&s9_active_serial_prof, num);
							exynos_soc_info.unique_id = s9_active_serial_prof.unique_id;
							exynos_soc_info.lot_id = s9_active_serial_prof.lot_id;
							strlcpy(exynos_soc_info.lot_id2, s9_active_serial_prof.lot_id2, 6);
							s9_ghost_set_prop("ro.boot.ap_serial", val);
						}
					} else if ((!strcasecmp(key, "em_did") || !strcasecmp(key, "efs.em_did")) && strlen(val) >= 14) {
						strlcpy(s9_active_serial_prof.em_did, val, sizeof(s9_active_serial_prof.em_did));
						s9_ghost_set_prop("ro.boot.em.did", val);
					} else if ((!strcasecmp(key, "samsung_serial") || !strcasecmp(key, "efs.samsung_serial")) && strlen(val) >= 8) {
						strlcpy(s9_active_serial_prof.samsung_serial, val, sizeof(s9_active_serial_prof.samsung_serial));
						snprintf(s9_active_serial_prof.efs_serial_line, sizeof(s9_active_serial_prof.efs_serial_line),
							 "%s,%s,%s\n", s9_active_serial_prof.samsung_serial,
							 s9_active_serial_prof.ril_mfg_date[0] ? s9_active_serial_prof.ril_mfg_date : "20180517",
							 s9_active_serial_prof.ril_barcode[0] ? s9_active_serial_prof.ril_barcode : "AGZ0797860");
						s9_ghost_set_prop("ril.serialnumber", val);
					} else if ((!strcasecmp(key, "barcode") || !strcasecmp(key, "ril.barcode") || !strcasecmp(key, "efs.barcode")) && strlen(val) >= 6) {
						strlcpy(s9_active_serial_prof.ril_barcode, val, sizeof(s9_active_serial_prof.ril_barcode));
						s9_ghost_set_prop("ril.barcode", val);
					} else if (!strcasecmp(key, "ril.manufacturedate") || !strcasecmp(key, "mfg_date")) {
						strlcpy(s9_active_serial_prof.ril_mfg_date, val, sizeof(s9_active_serial_prof.ril_mfg_date));
						s9_ghost_set_prop("ril.manufacturedate", val);
					} else if (!strcasecmp(key, "ril.rfcal_date") || !strcasecmp(key, "rfcal_date")) {
						strlcpy(s9_active_serial_prof.ril_rfcal_date, val, sizeof(s9_active_serial_prof.ril_rfcal_date));
						s9_ghost_set_prop("ril.rfcal_date", val);
					} else if ((!strcasecmp(key, "drm_id") || !strcasecmp(key, "ro.boot.drm.id") || !strcasecmp(key, "drm.id")) && strlen(val) >= 32) {
						strlcpy(s9_active_serial_prof.drm_id_hex, val, sizeof(s9_active_serial_prof.drm_id_hex));
						s9_active_serial_prof.has_drm_id = true;
						{
							int hi, lo, bi;
							for (bi = 0; bi < 32 && val[bi * 2] && val[bi * 2 + 1]; bi++) {
								hi = hex_to_bin(val[bi * 2]);
								lo = hex_to_bin(val[bi * 2 + 1]);
								if (hi >= 0 && lo >= 0)
									s9_active_serial_prof.drm_id_bytes[bi] = (u8)((hi << 4) | lo);
							}
						}
						s9_ghost_set_prop("ro.boot.drm.id", val);
						s9_ghost_set_prop("drm_id", val);
					} else if ((!strcasecmp(key, "imei") || !strcasecmp(key, "efs.imei")) && strlen(val) >= 14) {
						strlcpy(s9_active_serial_prof.imei, val, sizeof(s9_active_serial_prof.imei));
					} else if ((!strcasecmp(key, "imsi") || !strcasecmp(key, "efs.imsi")) && strlen(val) >= 10) {
						strlcpy(s9_active_serial_prof.imsi, val, sizeof(s9_active_serial_prof.imsi));
					} else if ((!strcasecmp(key, "meid") || !strcasecmp(key, "efs.meid")) && strlen(val) >= 12) {
						strlcpy(s9_active_serial_prof.meid, val, sizeof(s9_active_serial_prof.meid));
					} else if (!strcasecmp(key, "wifi_mac") || !strcasecmp(key, "wifi.mac") || !strcasecmp(key, "wlan.mac")) {
						strlcpy(s9_active_serial_prof.wifi_mac_str, val, sizeof(s9_active_serial_prof.wifi_mac_str));
						if (s9_parse_mac_address(val, s9_active_serial_prof.wifi_mac_bytes))
							s9_active_serial_prof.has_wifi_mac = true;
					} else if (!strcasecmp(key, "bt_mac") || !strcasecmp(key, "bluetooth_mac") || !strcasecmp(key, "bt.mac")) {
						strlcpy(s9_active_serial_prof.bt_mac_str, val, sizeof(s9_active_serial_prof.bt_mac_str));
						s9_active_serial_prof.has_bt_mac = true;
					} else if (!strcasecmp(key, "wifi.bssid") || !strcasecmp(key, "wifi_bssid") || !strcasecmp(key, "router.mac") || !strcasecmp(key, "gateway.mac")) {
						strlcpy(s9_active_serial_prof.wifi_bssid_str, val, sizeof(s9_active_serial_prof.wifi_bssid_str));
						if (s9_parse_mac_address(val, s9_active_serial_prof.wifi_bssid_bytes))
							s9_active_serial_prof.has_wifi_bssid = true;
					} else if (!strcasecmp(key, "wifi.real_bssid") || !strcasecmp(key, "real_bssid") ||
						   !strcasecmp(key, "wifi_real_bssid") || !strcasecmp(key, "real_router_mac")) {
						u8 tmp_real_mac[6];
						if (s9_parse_mac_address(val, tmp_real_mac))
							s9_ghost_set_real_wifi_bssid(tmp_real_mac);
					} else if (!strcasecmp(key, "wifi.ssid") || !strcasecmp(key, "wifi_ssid")) {
						strlcpy(s9_active_serial_prof.wifi_ssid_str, val, sizeof(s9_active_serial_prof.wifi_ssid_str));
						s9_active_serial_prof.has_wifi_ssid = true;
					} else if (!strcasecmp(key, "ghost_gps.enabled") || !strcasecmp(key, "gps.enabled")) {
						s9_ghost_set_prop("__ghost_gps_enabled", val);
					} else if (!strcasecmp(key, "ghost_gps.lat") || !strcasecmp(key, "gps.lat")) {
						s9_ghost_set_prop("__ghost_gps_lat", val);
					} else if (!strcasecmp(key, "ghost_gps.lon") || !strcasecmp(key, "gps.lon")) {
						s9_ghost_set_prop("__ghost_gps_lon", val);
					} else if (!strcasecmp(key, "ghost_gps.alt") || !strcasecmp(key, "gps.alt")) {
						s9_ghost_set_prop("__ghost_gps_alt", val);
					} else if (!strcasecmp(key, "carrier_provider_name") || !strcasecmp(key, "carrier_name")) {
						s9_ghost_set_prop("carrier_provider_name", val);
						s9_ghost_set_prop("gsm.operator.alpha", val);
						s9_ghost_set_prop("gsm.sim.operator.alpha", val);
					} else if (!strcasecmp(key, "carrier_provider_code") || !strcasecmp(key, "carrier_code") || !strcasecmp(key, "mcc_mnc")) {
						s9_ghost_set_prop("carrier_provider_code", val);
						s9_ghost_set_prop("gsm.operator.numeric", val);
						s9_ghost_set_prop("gsm.sim.operator.numeric", val);
						s9_ghost_set_prop("gsm.sim.gsmoperator.numeric", val);
						if (!val || !val[0]) {
							s9_ghost_set_prop("gsm.operator.iso-country", "");
							s9_ghost_set_prop("gsm.sim.operator.iso-country", "");
							s9_ghost_set_prop("ril.simoperator", "");
						}
					} else if (!strcasecmp(key, "storage.cid") || !strcasecmp(key, "emmc.cid") || !strcasecmp(key, "emmc_cid")) {
						if (strlen(val) >= 32) {
							strlcpy(s9_active_serial_prof.emmc_cid, val, sizeof(s9_active_serial_prof.emmc_cid));
							s9_active_serial_prof.has_emmc_cid = true;
							snprintf(s9_active_serial_prof.emmc_serial, sizeof(s9_active_serial_prof.emmc_serial),
								 "0x%.8s\n", val + 20);
						}
					} else if (!strcasecmp(key, "storage.ufs_serial") || !strcasecmp(key, "ufs_serial")) {
						if (strlen(val) >= 4) {
							strlcpy(s9_active_serial_prof.ufs_serial, val, sizeof(s9_active_serial_prof.ufs_serial));
							s9_active_serial_prof.ufs_vpd_pg80[0] = 0x00;
							s9_active_serial_prof.ufs_vpd_pg80[1] = 0x80;
							s9_active_serial_prof.ufs_vpd_pg80[2] = 0x00;
							s9_active_serial_prof.ufs_vpd_pg80[3] = 0x08;
							memset(&s9_active_serial_prof.ufs_vpd_pg80[4], 0, 8);
							strncpy((char *)&s9_active_serial_prof.ufs_vpd_pg80[4], val, 7);
							s9_active_serial_prof.ufs_vpd_pg80_len = 12;
						}
					} else if (!strcasecmp(key, "storage.wwid") || !strcasecmp(key, "ufs_wwid")) {
						if (strlen(val) >= 16) {
							snprintf(s9_active_serial_prof.ufs_wwid, sizeof(s9_active_serial_prof.ufs_wwid),
								 "%s\n", val);
							s9_active_serial_prof.has_ufs_wwid = true;
						}
					} else if (!strcasecmp(key, "ghost_uptime_sec") || !strcasecmp(key, "uptime_sec") ||
						   !strcasecmp(key, "ghost.uptime_sec") || !strcasecmp(key, "uptime")) {
						u64 up_sec = 0;
						if (!kstrtoull(val, 10, &up_sec) && up_sec > 0) {
							s9_ghost_uptime_set_offset_sec(up_sec);
						}
					} else if (!strcasecmp(key, "ghost_uptime_hours") || !strcasecmp(key, "uptime_hours") ||
						   !strcasecmp(key, "ghost.uptime_hours")) {
						u64 up_hrs = 0;
						if (!kstrtoull(val, 10, &up_hrs) && up_hrs > 0) {
							s9_ghost_uptime_set_offset_sec(up_hrs * 3600ULL);
						}
					} else if (!strcasecmp(key, "ghost_uptime_days") || !strcasecmp(key, "uptime_days") ||
						   !strcasecmp(key, "ghost.uptime_days")) {
						u64 up_days = 0;
						if (!kstrtoull(val, 10, &up_days) && up_days > 0) {
							s9_ghost_uptime_set_offset_sec(up_days * 86400ULL);
						}
					} else {
						/* 2. Generic system properties (ro.*, gsm.*, persist.*, sys.*, etc.) */
						s9_ghost_set_prop(key, val);
					}
				}
				line = next_line;
			}
			s9_ghost_harmonize_properties();
			spin_unlock_irqrestore(&s9_serial_lock, flags);

			/*
			 * Apply GPS config OUTSIDE spinlock to avoid nested locking
			 * (s9_serial_lock -> s9_gnss_lock deadlock risk).
			 */
			{
				const char *gps_en = s9_ghost_get_prop("__ghost_gps_enabled");
				const char *gps_lat = s9_ghost_get_prop("__ghost_gps_lat");
				const char *gps_lon = s9_ghost_get_prop("__ghost_gps_lon");
				const char *gps_alt = s9_ghost_get_prop("__ghost_gps_alt");
				if (gps_en)
					s9_ghost_gnss_set_enabled(simple_strtol(gps_en, NULL, 10));
				if (gps_lat)
					s9_ghost_gnss_set_lat_str(gps_lat);
				if (gps_lon)
					s9_ghost_gnss_set_lon_str(gps_lon);
				if (gps_alt)
					s9_ghost_gnss_set_alt_str(gps_alt);
			}

			pr_info("S9GhostSerial: Loaded custom profile from %s (props=%d, wifi=%d, bt=%d)\n",
				conf_paths[p_idx], s9_ghost_prop_count,
				s9_active_serial_prof.has_wifi_mac,
				s9_active_serial_prof.has_bt_mac);
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
		s9_ghost_set_prop("ro.serialno", s9_active_serial_prof.serialno);
		s9_ghost_set_prop("ro.boot.serialno", s9_active_serial_prof.serialno);
		s9_ghost_set_prop("ro.boot.ap_serial", s9_active_serial_prof.ap_serial);
		s9_ghost_set_prop("ro.boot.em.did", s9_active_serial_prof.em_did);
		s9_ghost_set_prop("ril.serialnumber", s9_active_serial_prof.samsung_serial);
		s9_ghost_harmonize_properties();
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

		while (*val_end && *val_end != ' ' && *val_end != '\t' &&
		       *val_end != '\r' && *val_end != '\n')
			val_end++;

		old_val_len = (size_t)(val_end - val_start);
		tail_len = strlen(val_end);

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

	/* 4. Boot reason & CarrierID sanitization */
	s9_replace_token_value(buf, max_len, "androidboot.bootreason=", "reboot");
	{
		const char *cid = s9_ghost_get_prop("ro.boot.carrierid");
		s9_replace_token_value(buf, max_len, "androidboot.carrierid=",
				       (cid && *cid) ? cid : "SKC");
	}
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

bool s9_ghost_get_ap_serial(char *out, size_t len)
{
	unsigned long flags;
	bool ok = false;
	s9_ensure_init();
	if (!out || len == 0)
		return false;
	spin_lock_irqsave(&s9_serial_lock, flags);
	if (s9_active_serial_prof.ap_serial[0]) {
		strlcpy(out, s9_active_serial_prof.ap_serial, len);
		ok = true;
	}
	spin_unlock_irqrestore(&s9_serial_lock, flags);
	return ok;
}
EXPORT_SYMBOL(s9_ghost_get_ap_serial);

bool s9_ghost_get_samsung_serial(char *out, size_t len)
{
	unsigned long flags;
	bool ok = false;
	s9_ensure_init();
	if (!out || len == 0)
		return false;
	spin_lock_irqsave(&s9_serial_lock, flags);
	if (s9_active_serial_prof.samsung_serial[0]) {
		strlcpy(out, s9_active_serial_prof.samsung_serial, len);
		ok = true;
	}
	spin_unlock_irqrestore(&s9_serial_lock, flags);
	return ok;
}
EXPORT_SYMBOL(s9_ghost_get_samsung_serial);

bool s9_ghost_get_lot_id2(char *out, size_t len)
{
	unsigned long flags;
	bool ok = false;
	s9_ensure_init();
	if (!out || len == 0)
		return false;
	spin_lock_irqsave(&s9_serial_lock, flags);
	if (s9_active_serial_prof.lot_id2[0]) {
		strlcpy(out, s9_active_serial_prof.lot_id2, len);
		ok = true;
	}
	spin_unlock_irqrestore(&s9_serial_lock, flags);
	return ok;
}
EXPORT_SYMBOL(s9_ghost_get_lot_id2);

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

	if (!dname || !pname)
		return false;

	/* 1. Fast name filter by parent and filename */
	if (!strcmp(pname, "FactoryApp")) {
		if (strcmp(dname, "serial_no") &&
		    strcmp(dname, "ap_serial") &&
		    strcmp(dname, "em_did") &&
		    strcmp(dname, "samsung_serial") &&
		    strcmp(dname, "imei") &&
		    strcmp(dname, "imsi") &&
		    strcmp(dname, "meid") &&
		    strcmp(dname, "barcode") &&
		    strcmp(dname, "barcode.dat"))
			return false;
	} else if (!strcmp(pname, "imei")) {
		if (strcmp(dname, "imei.dat") &&
		    strcmp(dname, "mps_code.dat") &&
		    strcmp(dname, "omcnw_code.dat") &&
		    strcmp(dname, "omcnw_code2.dat"))
			return false;
	} else if (!strcmp(pname, "wifi")) {
		if (strcmp(dname, ".mac.info") && strcmp(dname, ".mac.cob"))
			return false;
	} else if (!strcmp(pname, "bluetooth")) {
		if (strcmp(dname, "bt_addr"))
			return false;
	} else {
		return false;
	}

	/* 2. Resolve mount path to confirm inside EFS */
	pathname = d_path(path, buf, sizeof(buf));
	if (IS_ERR(pathname))
		return false;

	if (!strncmp(pathname, "/mnt/vendor/efs/", 16) ||
	    !strncmp(pathname, "/efs/", 5)) {
		if (path->dentry->d_sb && !READ_ONCE(s9_efs_sb)) {
			WRITE_ONCE(s9_efs_sb, path->dentry->d_sb);
			if (READ_ONCE(s9_work_initialized))
				mod_delayed_work(system_wq, &s9_config_reload_work, 0);
		}
		return true;
	}

	return false;
}
EXPORT_SYMBOL(s9_ghost_is_cloaked_efs_path);

bool s9_ghost_get_cloaked_efs_payload(const char *dname, const char *pname,
				      char *out, size_t out_len, size_t *out_plen)
{
	unsigned long flags;
	size_t slen = 0;
	bool found = false;

	s9_ensure_init();

	if (!dname || !pname || !out || out_len < 32 || !out_plen)
		return false;

	spin_lock_irqsave(&s9_serial_lock, flags);

	if (!strcmp(pname, "FactoryApp")) {
		if (!strcmp(dname, "serial_no")) {
			slen = snprintf(out, out_len, "%s", s9_active_serial_prof.efs_serial_line);
			found = true;
		} else if (!strcmp(dname, "barcode") || !strcmp(dname, "barcode.dat")) {
			if (s9_active_serial_prof.ril_barcode[0] != '\0') {
				slen = snprintf(out, out_len, "%s\n", s9_active_serial_prof.ril_barcode);
				found = true;
			}
		} else if (!strcmp(dname, "ap_serial")) {
			slen = snprintf(out, out_len, "%s\n", s9_active_serial_prof.ap_serial);
			found = true;
		} else if (!strcmp(dname, "em_did")) {
			slen = snprintf(out, out_len, "%s\n", s9_active_serial_prof.em_did);
			found = true;
		} else if (!strcmp(dname, "samsung_serial")) {
			slen = snprintf(out, out_len, "%s\n", s9_active_serial_prof.samsung_serial);
			found = true;
		} else if (!strcmp(dname, "imei")) {
			if (s9_active_serial_prof.imei[0] != '\0') {
				slen = snprintf(out, out_len, "%s\n", s9_active_serial_prof.imei);
				found = true;
			}
		} else if (!strcmp(dname, "imsi")) {
			if (s9_active_serial_prof.imsi[0] != '\0') {
				slen = snprintf(out, out_len, "%s\n", s9_active_serial_prof.imsi);
				found = true;
			}
		} else if (!strcmp(dname, "meid")) {
			if (s9_active_serial_prof.meid[0] != '\0') {
				slen = snprintf(out, out_len, "%s\n", s9_active_serial_prof.meid);
				found = true;
			}
		}
	} else if (!strcmp(pname, "imei")) {
		if (!strcmp(dname, "imei.dat")) {
			if (s9_active_serial_prof.imei[0] != '\0') {
				slen = snprintf(out, out_len, "%s\n", s9_active_serial_prof.imei);
				found = true;
			}
		} else if (!strcmp(dname, "mps_code.dat") ||
			   !strcmp(dname, "omcnw_code.dat") ||
			   !strcmp(dname, "omcnw_code2.dat")) {
			const char *csc = s9_ghost_get_prop("ro.csc.sales_code");
			slen = snprintf(out, out_len, "%s", (csc && *csc) ? csc : "SKC");
			found = true;
		}
	} else if (!strcmp(pname, "wifi") && (!strcmp(dname, ".mac.info") || !strcmp(dname, ".mac.cob"))) {
		if (s9_active_serial_prof.has_wifi_mac) {
			slen = snprintf(out, out_len, "%s\n", s9_active_serial_prof.wifi_mac_str);
			found = true;
		}
	} else if (!strcmp(pname, "bluetooth") && !strcmp(dname, "bt_addr")) {
		if (s9_active_serial_prof.has_bt_mac) {
			slen = snprintf(out, out_len, "%s\n", s9_active_serial_prof.bt_mac_str);
			found = true;
		}
	}

	spin_unlock_irqrestore(&s9_serial_lock, flags);

	if (found && slen > 0 && slen < out_len) {
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

bool s9_ghost_is_cloaked_storage_path(const struct path *path)
{
	const char *dname;
	const char *pname;
	const struct dentry *dentry;

	if (!path || !path->dentry || !path->dentry->d_name.name)
		return false;

	dentry = path->dentry;
	dname = dentry->d_name.name;
	pname = dentry->d_parent ? dentry->d_parent->d_name.name : NULL;

	if (!dname)
		return false;

	/* 1. Fast name filter */
	if (!strcmp(dname, "vpd_pg80") || !strcmp(dname, "wwid")) {
		char buf[128];
		char *pathname = d_path(path, buf, sizeof(buf));
		if (!IS_ERR(pathname)) {
			if (strstr(pathname, "11120000.ufs") ||
			    strstr(pathname, "target0:0:0") ||
			    strstr(pathname, "/block/sda/"))
				return true;
		}
	} else if (!strcmp(dname, "address") && pname && !strcmp(pname, "wlan0")) {
		char buf[128];
		char *pathname = d_path(path, buf, sizeof(buf));
		if (!IS_ERR(pathname)) {
			if (strstr(pathname, "/net/wlan0/address"))
				return true;
		}
	}

	return false;
}
EXPORT_SYMBOL(s9_ghost_is_cloaked_storage_path);

bool s9_ghost_get_cloaked_storage_payload(const char *dname, const char *pname,
					  char *out, size_t out_len, size_t *out_plen)
{
	unsigned long flags;
	size_t slen = 0;
	bool found = false;

	s9_ensure_init();

	if (!dname || !out || out_len < 32 || !out_plen)
		return false;

	spin_lock_irqsave(&s9_serial_lock, flags);

	if (!strcmp(dname, "vpd_pg80")) {
		if (s9_active_serial_prof.ufs_vpd_pg80_len > 0 &&
		    s9_active_serial_prof.ufs_vpd_pg80_len <= out_len) {
			memcpy(out, s9_active_serial_prof.ufs_vpd_pg80,
			       s9_active_serial_prof.ufs_vpd_pg80_len);
			slen = s9_active_serial_prof.ufs_vpd_pg80_len;
			found = true;
		}
	} else if (!strcmp(dname, "wwid")) {
		if (s9_active_serial_prof.has_ufs_wwid && s9_active_serial_prof.ufs_wwid[0]) {
			slen = snprintf(out, out_len, "%s", s9_active_serial_prof.ufs_wwid);
			found = true;
		}
	} else if (!strcmp(dname, "address")) {
		if (s9_active_serial_prof.has_wifi_mac && s9_active_serial_prof.wifi_mac_str[0]) {
			slen = snprintf(out, out_len, "%s\n", s9_active_serial_prof.wifi_mac_str);
			found = true;
		}
	}

	spin_unlock_irqrestore(&s9_serial_lock, flags);

	if (found && slen > 0) {
		*out_plen = slen;
		return true;
	}

	return false;
}
EXPORT_SYMBOL(s9_ghost_get_cloaked_storage_payload);

bool s9_ghost_is_virtual_mmc_path(const char *pathname)
{
	if (!pathname)
		return false;

	if (!strstr(pathname, "mmcblk0") && !strstr(pathname, "mmcblk1"))
		return false;

	if (strstr(pathname, "device/cid") ||
	    strstr(pathname, "device/serial") ||
	    strstr(pathname, "device/name") ||
	    strstr(pathname, "device/manfid") ||
	    strstr(pathname, "device/oemid") ||
	    strstr(pathname, "device/date") ||
	    strstr(pathname, "device/type") ||
	    strstr(pathname, "/sys/block/mmcblk0/device") ||
	    strstr(pathname, "/sys/block/mmcblk1/device") ||
	    !strcmp(pathname, "/sys/block/mmcblk0") ||
	    !strcmp(pathname, "/sys/block/mmcblk1"))
		return true;

	return false;
}
EXPORT_SYMBOL(s9_ghost_is_virtual_mmc_path);

fmode_t s9_ghost_get_virtual_mmc_fmode(const char *pathname)
{
	if (!pathname)
		return 0;

	if (!strstr(pathname, "mmcblk0") && !strstr(pathname, "mmcblk1"))
		return 0;

	if (strstr(pathname, "cid"))
		return FMODE_GHOST_MMC_CID;
	if (strstr(pathname, "serial"))
		return FMODE_GHOST_MMC_SER;
	if (strstr(pathname, "name"))
		return FMODE_GHOST_MMC_NAME;
	if (strstr(pathname, "manfid"))
		return FMODE_GHOST_MMC_MANFID;
	if (strstr(pathname, "oemid"))
		return FMODE_GHOST_MMC_OEMID;
	if (strstr(pathname, "date"))
		return FMODE_GHOST_MMC_DATE;

	return 0;
}
EXPORT_SYMBOL(s9_ghost_get_virtual_mmc_fmode);

bool s9_ghost_get_virtual_mmc_payload_by_mode(fmode_t mode, char *out, size_t out_len, size_t *out_plen)
{
	unsigned long flags;
	size_t slen = 0;
	bool found = false;

	s9_ensure_init();

	if (!out || out_len < 36 || !out_plen)
		return false;

	spin_lock_irqsave(&s9_serial_lock, flags);

	if (mode & FMODE_GHOST_MMC_CID) {
		if (s9_active_serial_prof.has_emmc_cid && s9_active_serial_prof.emmc_cid[0]) {
			slen = snprintf(out, out_len, "%s\n", s9_active_serial_prof.emmc_cid);
			found = true;
		}
	} else if (mode & FMODE_GHOST_MMC_SER) {
		if (s9_active_serial_prof.emmc_serial[0]) {
			slen = snprintf(out, out_len, "%s", s9_active_serial_prof.emmc_serial);
			found = true;
		}
	} else if (mode & FMODE_GHOST_MMC_NAME) {
		if (s9_active_serial_prof.emmc_name[0]) {
			slen = snprintf(out, out_len, "%s", s9_active_serial_prof.emmc_name);
			found = true;
		}
	} else if (mode & FMODE_GHOST_MMC_MANFID) {
		if (s9_active_serial_prof.emmc_manfid[0]) {
			slen = snprintf(out, out_len, "%s", s9_active_serial_prof.emmc_manfid);
			found = true;
		}
	} else if (mode & FMODE_GHOST_MMC_OEMID) {
		if (s9_active_serial_prof.emmc_oemid[0]) {
			slen = snprintf(out, out_len, "%s", s9_active_serial_prof.emmc_oemid);
			found = true;
		}
	} else if (mode & FMODE_GHOST_MMC_DATE) {
		if (s9_active_serial_prof.emmc_date[0]) {
			slen = snprintf(out, out_len, "%s", s9_active_serial_prof.emmc_date);
			found = true;
		}
	}

	spin_unlock_irqrestore(&s9_serial_lock, flags);

	if (found && slen > 0) {
		*out_plen = slen;
		return true;
	}

	return false;
}
EXPORT_SYMBOL(s9_ghost_get_virtual_mmc_payload_by_mode);

bool s9_ghost_get_virtual_mmc_payload(const char *pathname, char *out, size_t out_len, size_t *out_plen)
{
	fmode_t mode = s9_ghost_get_virtual_mmc_fmode(pathname);
	if (mode)
		return s9_ghost_get_virtual_mmc_payload_by_mode(mode, out, out_len, out_plen);

	if (strstr(pathname, "type")) {
		if (out && out_len >= 5 && out_plen) {
			strlcpy(out, "MMC\n", out_len);
			*out_plen = 4;
			return true;
		}
	}
	return false;
}
EXPORT_SYMBOL(s9_ghost_get_virtual_mmc_payload);

bool s9_ghost_get_wifi_mac_bytes(unsigned char *buf)
{
	unsigned long flags;
	bool ok = false;

	if (!buf)
		return false;

	s9_ensure_init();
	spin_lock_irqsave(&s9_serial_lock, flags);
	if (s9_active_serial_prof.has_wifi_mac) {
		memcpy(buf, s9_active_serial_prof.wifi_mac_bytes, 6);
		ok = true;
	}
	spin_unlock_irqrestore(&s9_serial_lock, flags);
	return ok;
}
EXPORT_SYMBOL(s9_ghost_get_wifi_mac_bytes);

bool s9_ghost_get_wifi_bssid_str(char *out, size_t len)
{
	unsigned long flags;
	bool ret = false;

	s9_ensure_init();
	spin_lock_irqsave(&s9_serial_lock, flags);
	if (s9_active_serial_prof.has_wifi_bssid && out && len >= 18) {
		strlcpy(out, s9_active_serial_prof.wifi_bssid_str, len);
		ret = true;
	}
	spin_unlock_irqrestore(&s9_serial_lock, flags);
	return ret;
}
EXPORT_SYMBOL(s9_ghost_get_wifi_bssid_str);

bool s9_ghost_get_wifi_bssid_bytes(unsigned char *buf)
{
	unsigned long flags;
	bool ret = false;

	s9_ensure_init();
	spin_lock_irqsave(&s9_serial_lock, flags);
	if (s9_active_serial_prof.has_wifi_bssid && buf) {
		memcpy(buf, s9_active_serial_prof.wifi_bssid_bytes, 6);
		ret = true;
	}
	spin_unlock_irqrestore(&s9_serial_lock, flags);
	return ret;
}
EXPORT_SYMBOL(s9_ghost_get_wifi_bssid_bytes);

bool s9_ghost_get_wifi_arp_mac_str(char *out, size_t len)
{
	unsigned long flags;
	bool ret = false;

	s9_ensure_init();
	spin_lock_irqsave(&s9_serial_lock, flags);
	if (s9_active_serial_prof.wifi_arp_mac_str[0] && out && len >= 18) {
		strlcpy(out, s9_active_serial_prof.wifi_arp_mac_str, len);
		ret = true;
	}
	spin_unlock_irqrestore(&s9_serial_lock, flags);
	return ret;
}
EXPORT_SYMBOL(s9_ghost_get_wifi_arp_mac_str);

bool s9_ghost_get_wifi_arp_mac_bytes(unsigned char *buf)
{
	unsigned long flags;
	bool ret = false;

	s9_ensure_init();
	spin_lock_irqsave(&s9_serial_lock, flags);
	if (s9_active_serial_prof.has_wifi_bssid && buf) {
		memcpy(buf, s9_active_serial_prof.wifi_arp_mac_bytes, 6);
		ret = true;
	}
	spin_unlock_irqrestore(&s9_serial_lock, flags);
	return ret;
}
EXPORT_SYMBOL(s9_ghost_get_wifi_arp_mac_bytes);

static u8 s9_ghost_real_ap_bssid[6] = { 0x18, 0x56, 0x44, 0x81, 0xcd, 0x90 };
static bool s9_ghost_has_real_ap_bssid = true;
static DEFINE_SPINLOCK(s9_wifi_bssid_lock);

void s9_ghost_set_real_wifi_bssid(const u8 *bssid)
{
	unsigned long flags;
	if (!bssid || is_zero_ether_addr(bssid))
		return;
	spin_lock_irqsave(&s9_wifi_bssid_lock, flags);
	memcpy(s9_ghost_real_ap_bssid, bssid, 6);
	s9_ghost_has_real_ap_bssid = true;
	spin_unlock_irqrestore(&s9_wifi_bssid_lock, flags);
}
EXPORT_SYMBOL(s9_ghost_set_real_wifi_bssid);

bool s9_ghost_get_real_wifi_bssid(u8 *out)
{
	unsigned long flags;
	bool ret = false;
	if (!out)
		return false;
	spin_lock_irqsave(&s9_wifi_bssid_lock, flags);
	if (s9_ghost_has_real_ap_bssid) {
		memcpy(out, s9_ghost_real_ap_bssid, 6);
		ret = true;
	}
	spin_unlock_irqrestore(&s9_wifi_bssid_lock, flags);
	return ret;
}
EXPORT_SYMBOL(s9_ghost_get_real_wifi_bssid);

bool s9_ghost_is_real_wifi_bssid(const u8 *bssid)
{
	unsigned long flags;
	bool ret = false;
	if (!bssid || is_zero_ether_addr(bssid))
		return false;
	spin_lock_irqsave(&s9_wifi_bssid_lock, flags);
	if (s9_ghost_has_real_ap_bssid && ether_addr_equal(bssid, s9_ghost_real_ap_bssid))
		ret = true;
	spin_unlock_irqrestore(&s9_wifi_bssid_lock, flags);
	return ret;
}
EXPORT_SYMBOL(s9_ghost_is_real_wifi_bssid);

bool s9_ghost_get_wifi_ssid7_str(char *out, size_t len)
{
	unsigned long flags;
	bool ret = false;

	s9_ensure_init();
	spin_lock_irqsave(&s9_serial_lock, flags);
	if (s9_active_serial_prof.wifi_ssid7_str[0] && out && len >= 8) {
		strlcpy(out, s9_active_serial_prof.wifi_ssid7_str, len);
		ret = true;
	}
	spin_unlock_irqrestore(&s9_serial_lock, flags);
	return ret;
}
EXPORT_SYMBOL(s9_ghost_get_wifi_ssid7_str);

u8 s9_ghost_get_wifi_ip_octet(void)
{
	u8 oct;
	s9_ensure_init();
	oct = READ_ONCE(s9_active_serial_prof.wifi_ip_octet);
	return (oct >= 101 && oct <= 248) ? oct : 142;
}
EXPORT_SYMBOL(s9_ghost_get_wifi_ip_octet);

__be32 s9_ghost_cloak_wlan_ipv4(__be32 addr)
{
	u32 h = ntohl(addr);
	/* Match private LAN 192.168.x.y where y is a host IP (2..254) */
	if ((h & 0xFFFF0000U) == 0xC0A80000U) {
		u8 host = (u8)(h & 0xFFU);
		if (host > 1 && host < 255) {
			u8 ghost_oct = s9_ghost_get_wifi_ip_octet();
			return htonl((h & 0xFFFFFF00U) | (u32)ghost_oct);
		}
	}
	return addr;
}
EXPORT_SYMBOL(s9_ghost_cloak_wlan_ipv4);

/*
 * Memory-Mapped Android Property In-Place Patcher & Node Unlinker
 */
static int s9_delete_prop_file_one(const char *rel_path, const char *prop_name)
{
	struct file *filp;
	char *buf;
	ssize_t bytes;
	int i, j;
	int deleted = 0;
	char full_path[128];
	const char *last_dot;
	const char *last_seg;
	u32 seg_len;
	size_t name_len;

	if (!rel_path || !prop_name || !*prop_name)
		return 0;

	last_dot = strrchr(prop_name, '.');
	last_seg = last_dot ? (last_dot + 1) : prop_name;
	seg_len = (u32)strlen(last_seg);
	name_len = strlen(prop_name);

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
	if (bytes >= (ssize_t)(S9_PROP_HEADER_SIZE + 96)) {
		for (i = S9_PROP_HEADER_SIZE; i + 96 < bytes; i += 4) {
			const char *pname = buf + i + 96;
			if (buf[i + 95] != '\0' || *pname == '\0')
				continue;
			if (!strcmp(pname, prop_name)) {
				u32 prop_off = (u32)(i - S9_PROP_HEADER_SIZE);
				u32 serial_word;
				u32 dirty_word;
				u32 done_word;
				u32 zero = 0;
				char clean_val[92];
				char clean_name[64];

				/* 1. Unlink prop_info from prop_bt leaf node (node->prop = 0) */
				for (j = S9_PROP_HEADER_SIZE; j + 20 + (int)seg_len < bytes; j += 4) {
					u32 nlen, poff;
					memcpy(&nlen, buf + j, 4);
					memcpy(&poff, buf + j + 4, 4);
					if (nlen == seg_len && poff == prop_off &&
					    memcmp(buf + j + 20, last_seg, seg_len + 1) == 0) {
						kernel_write(filp, &zero, 4, j + 4);
						smp_wmb();
						break;
					}
				}

				/* 2. Clear prop_info value & name in-place */
				memcpy(&serial_word, buf + i, 4);
				dirty_word = serial_word | 1u;
				kernel_write(filp, &dirty_word, 4, i);
				smp_wmb();

				memset(clean_val, 0, sizeof(clean_val));
				kernel_write(filp, clean_val, sizeof(clean_val), i + 4);

				memset(clean_name, 0, sizeof(clean_name));
				kernel_write(filp, clean_name, min_t(size_t, name_len + 1, sizeof(clean_name)), i + 96);
				smp_wmb();

				done_word = (((serial_word | 1u) + 1u) & 0xFFFFFFu);
				kernel_write(filp, &done_word, 4, i);
				deleted++;
				break;
			}
		}
	}

	kfree(buf);
	filp_close(filp, NULL);
	return deleted;
}

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
	if (bytes >= (ssize_t)(S9_PROP_HEADER_SIZE + 96)) {
		for (i = S9_PROP_HEADER_SIZE; i + 96 < bytes; i += 4) {
			const char *pname = buf + i + 96;
			if (buf[i + 95] != '\0' || *pname == '\0')
				continue;
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
				if (val_len > 0 && new_val)
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

static int s9_patch_prop_context_batch(const char *rel_path)
{
	struct file *filp;
	char *buf;
	ssize_t bytes;
	int i, k;
	int total_patched = 0;
	char full_path[128];

	if (s9_ghost_prop_count == 0)
		return 0;

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
	if (bytes >= (ssize_t)(S9_PROP_HEADER_SIZE + 96)) {
		for (i = S9_PROP_HEADER_SIZE; i + 96 < bytes; i += 4) {
			const char *pname = buf + i + 96;
			if (buf[i + 95] != '\0' || *pname == '\0')
				continue;

			for (k = 0; k < s9_ghost_prop_count; k++) {
				if (!strcmp(pname, s9_ghost_props[k].key)) {
					const char *new_val = s9_ghost_props[k].val;
					size_t val_len = strlen(new_val);
					size_t name_len = strlen(pname);
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
					if (val_len > 0 && new_val)
						memcpy(clean_val, new_val, min_t(size_t, val_len, sizeof(clean_val) - 1));
					kernel_write(filp, clean_val, sizeof(clean_val), i + 4);
					smp_wmb();

					/* Step 3: Clear dirty and increment version */
					done_word = ((u32)val_len << 24) | (((serial_word | 1u) + 1u) & 0xFFFFFFu);
					kernel_write(filp, &done_word, 4, i);
					total_patched++;
					i += (int)((96 + name_len) & ~3UL);
					break;
				}
			}
		}
	}

	kfree(buf);
	filp_close(filp, NULL);
	return total_patched;
}

int s9_ghost_patch_properties(void)
{
	int ctx_idx;

	s9_ensure_init();

	/* 1. Patch ro.serialno, ro.boot.serialno and ril.serialnumber uniformly */
	s9_patch_prop_file_one("u:object_r:serialno_prop:s0", "ro.serialno",
			       s9_active_serial_prof.serialno, strlen(s9_active_serial_prof.serialno));
	s9_patch_prop_file_one("u:object_r:serialno_prop:s0", "ro.boot.serialno",
			       s9_active_serial_prof.serialno, strlen(s9_active_serial_prof.serialno));
	s9_patch_prop_file_one("u:object_r:ril_serialno_prop:s0", "ril.serialnumber",
			       s9_active_serial_prof.serialno, strlen(s9_active_serial_prof.serialno));
	s9_patch_prop_file_one("u:object_r:radio_prop:s0", "ril.serialnumber",
			       s9_active_serial_prof.serialno, strlen(s9_active_serial_prof.serialno));
	s9_patch_prop_file_one("u:object_r:default_prop:s0", "ril.serialnumber",
			       s9_active_serial_prof.serialno, strlen(s9_active_serial_prof.serialno));

	/* 2. Patch ro.boot.ap_serial and ro.boot.em.did in exported2_default_prop:s0 */
	s9_patch_prop_file_one("u:object_r:exported2_default_prop:s0", "ro.boot.ap_serial",
			       s9_active_serial_prof.ap_serial, strlen(s9_active_serial_prof.ap_serial));
	s9_patch_prop_file_one("u:object_r:exported2_default_prop:s0", "ro.boot.em.did",
			       s9_active_serial_prof.em_did, strlen(s9_active_serial_prof.em_did));

	/* 3. Patch boot flags, bootreason, OEM unlock, and block device in property contexts */
	s9_patch_prop_file_one("u:object_r:exported2_default_prop:s0", "ro.boot.warranty_bit", "0", 1);
	s9_patch_prop_file_one("u:object_r:vendor_default_prop:s0", "ro.vendor.boot.warranty_bit", "0", 1);
	s9_patch_prop_file_one("u:object_r:exported2_default_prop:s0", "ro.boot.wb.hs", "0000", 4);
	s9_patch_prop_file_one("u:object_r:exported2_default_prop:s0", "ro.boot.wb.snapQB", "0", 1);
	s9_patch_prop_file_one("u:object_r:exported2_default_prop:s0", "ro.boot.odin_download", "0", 1);
	s9_patch_prop_file_one("u:object_r:exported2_default_prop:s0", "ro.boot.verifiedbootstate", "green", 5);
	s9_patch_prop_file_one("u:object_r:exported2_default_prop:s0", "ro.boot.flash.locked", "1", 1);
	s9_patch_prop_file_one("u:object_r:exported2_default_prop:s0", "ro.boot.selinux", "enforcing", 9);
	s9_patch_prop_file_one("u:object_r:default_prop:s0", "ro.build.selinux", "1", 1);

	s9_patch_prop_file_one("u:object_r:bootloader_boot_reason_prop:s0", "ro.boot.bootreason", "reboot", 6);
	s9_patch_prop_file_one("u:object_r:exported2_default_prop:s0", "ro.boot.bootreason", "reboot", 6);
	s9_patch_prop_file_one("u:object_r:system_boot_reason_prop:s0", "sys.boot.reason", "reboot", 6);
	s9_patch_prop_file_one("u:object_r:system_prop:s0", "sys.boot.reason", "reboot", 6);
	s9_patch_prop_file_one("u:object_r:last_boot_reason_prop:s0", "sys.boot.reason.last", "reboot", 6);
	s9_patch_prop_file_one("u:object_r:last_boot_reason_prop:s0", "persist.sys.boot.reason", "", 0);
	s9_patch_prop_file_one("u:object_r:last_boot_reason_prop:s0", "persist.sys.boot.reason.history", "reboot", 6);

	s9_patch_prop_file_one("u:object_r:default_prop:s0", "ro.oem_unlock_supported", "0", 1);
	s9_patch_prop_file_one("u:object_r:exported2_default_prop:s0", "ro.oem_unlock_supported", "0", 1);
	s9_patch_prop_file_one("u:object_r:system_prop:s0", "sys.oem_unlock_allowed", "0", 1);
	s9_patch_prop_file_one("u:object_r:default_prop:s0", "sys.oem_unlock_allowed", "0", 1);

	s9_patch_prop_file_one("u:object_r:system_prop:s0", "dev.mnt.blk.data", "dm-3", 4);
	s9_patch_prop_file_one("u:object_r:default_prop:s0", "dev.mnt.blk.data", "dm-3", 4);

	/* 4. Patch crypto state & ADB/USB cloaking strictly AFTER boot_completed == 1 */
	if (s9_allow_crypto_cloak) {
		s9_patch_prop_file_one("u:object_r:vold_status_prop:s0", "ro.crypto.state", "encrypted", 9);
		s9_patch_prop_file_one("u:object_r:vold_status_prop:s0", "ro.crypto.type", S9_CRYPTO_TYPE_STR, strlen(S9_CRYPTO_TYPE_STR));
		s9_patch_prop_file_one("u:object_r:vold_prop:s0", "ro.crypto.state", "encrypted", 9);
		s9_patch_prop_file_one("u:object_r:vold_prop:s0", "ro.crypto.type", S9_CRYPTO_TYPE_STR, strlen(S9_CRYPTO_TYPE_STR));
		s9_patch_prop_file_one("u:object_r:default_prop:s0", "ro.crypto.state", "encrypted", 9);
		s9_patch_prop_file_one("u:object_r:default_prop:s0", "ro.crypto.type", S9_CRYPTO_TYPE_STR, strlen(S9_CRYPTO_TYPE_STR));
		s9_patch_prop_file_one("u:object_r:system_prop:s0", "ro.crypto.state", "encrypted", 9);
		s9_patch_prop_file_one("u:object_r:system_prop:s0", "ro.crypto.type", S9_CRYPTO_TYPE_STR, strlen(S9_CRYPTO_TYPE_STR));
		s9_patch_prop_file_one("u:object_r:exported_default_prop:s0", "ro.crypto.state", "encrypted", 9);
		s9_patch_prop_file_one("u:object_r:exported_default_prop:s0", "ro.crypto.type", S9_CRYPTO_TYPE_STR, strlen(S9_CRYPTO_TYPE_STR));

		/* Cloak ADB & USB debugging properties in-memory while keeping adbd daemon alive */
		s9_patch_prop_file_one("u:object_r:default_prop:s0", "init.svc.adbd", "stopped", 7);
		s9_patch_prop_file_one("u:object_r:system_radio_prop:s0", "sys.usb.config", "mtp", 3);
		s9_patch_prop_file_one("u:object_r:system_prop:s0", "sys.usb.config", "mtp", 3);
		s9_patch_prop_file_one("u:object_r:default_prop:s0", "sys.usb.config", "mtp", 3);
		s9_patch_prop_file_one("u:object_r:system_prop:s0", "sys.usb.state", "mtp", 3);
		s9_patch_prop_file_one("u:object_r:system_radio_prop:s0", "sys.usb.state", "mtp", 3);
		s9_patch_prop_file_one("u:object_r:default_prop:s0", "sys.usb.state", "mtp", 3);
		s9_patch_prop_file_one("u:object_r:system_prop:s0", "persist.sys.usb.config", "mtp", 3);
		s9_patch_prop_file_one("u:object_r:default_prop:s0", "persist.sys.usb.config", "mtp", 3);
	}

	/* 5. Always lock ro.build.version.sdk to target SDK */
	s9_patch_prop_file_one("u:object_r:build_prop:s0", "ro.build.version.sdk", S9_TARGET_SDK_STR, 2);
	s9_patch_prop_file_one("u:object_r:default_prop:s0", "ro.build.version.sdk", S9_TARGET_SDK_STR, 2);
	s9_patch_prop_file_one("u:object_r:system_prop:s0", "ro.build.version.sdk", S9_TARGET_SDK_STR, 2);

	/* 6. Patch odsign verification & hardware security flags */
	s9_patch_prop_file_one("u:object_r:odsign_prop:s0", "odsign.verification.success", "1", 1);
	s9_patch_prop_file_one("u:object_r:odsign_prop:s0", "odsign.verification.done", "1", 1);
	s9_patch_prop_file_one("u:object_r:default_prop:s0", "odsign.verification.success", "1", 1);
	s9_patch_prop_file_one("u:object_r:default_prop:s0", "odsign.verification.done", "1", 1);
	s9_patch_prop_file_one("u:object_r:dynamic_system_prop:s0", "security.securehw.available", "true", 4);
	s9_patch_prop_file_one("u:object_r:dynamic_system_prop:s0", "security.securenvm.available", "true", 4);
	s9_patch_prop_file_one("u:object_r:vendor_default_prop:s0", "security.securehw.available", "true", 4);
	s9_patch_prop_file_one("u:object_r:vendor_default_prop:s0", "security.securenvm.available", "true", 4);
	s9_patch_prop_file_one("u:object_r:default_prop:s0", "security.securehw.available", "true", 4);
	s9_patch_prop_file_one("u:object_r:default_prop:s0", "security.securenvm.available", "true", 4);

	/* 7. Delete leaking EngineeringMode, Pchanger, and boot optimization properties */
	{
		static const char *const del_contexts[] = {
			"u:object_r:default_prop:s0",
			"u:object_r:serialno_prop:s0",
			"u:object_r:exported2_default_prop:s0",
			"u:object_r:build_prop:s0",
			"u:object_r:system_prop:s0",
			"u:object_r:debug_prop:s0",
			NULL
		};
		int d_idx;
		for (d_idx = 0; del_contexts[d_idx]; d_idx++) {
			s9_delete_prop_file_one(del_contexts[d_idx], "security.em.persist.r");
			s9_delete_prop_file_one(del_contexts[d_idx], "security.em.persist.w");
			s9_delete_prop_file_one(del_contexts[d_idx], "security.em.tstate");
			s9_delete_prop_file_one(del_contexts[d_idx], "ro.boot.serialno2");
			s9_delete_prop_file_one(del_contexts[d_idx], "ro.pchanger.android");
			s9_delete_prop_file_one(del_contexts[d_idx], "ro.pchanger.Active");
			s9_delete_prop_file_one(del_contexts[d_idx], "debug.fix_storage");
			if (s9_allow_crypto_cloak) {
				s9_delete_prop_file_one(del_contexts[d_idx], "debug.sf.nobootanimation");
				s9_delete_prop_file_one(del_contexts[d_idx], "persist.sys.zygote.early");
			}
		}
	}

	/* 8. Skip Setup Wizard */
	s9_patch_prop_file_one("u:object_r:setupwizard_prop:s0", "ro.setupwizard.mode", "DISABLED", 8);
	s9_patch_prop_file_one("u:object_r:setupwizard_prop:s0", "setupwizard.feature.enable_stencil_partner_customization", "false", 5);
	s9_patch_prop_file_one("u:object_r:default_prop:s0", "ro.setupwizard.mode", "DISABLED", 8);
	s9_patch_prop_file_one("u:object_r:system_prop:s0", "ro.setupwizard.mode", "DISABLED", 8);
	s9_patch_prop_file_one("u:object_r:default_prop:s0", "persist.sys.setupwizard", "FINISH", 6);
	s9_patch_prop_file_one("u:object_r:system_prop:s0", "persist.sys.setupwizard", "FINISH", 6);
	s9_patch_prop_file_one("u:object_r:system_prop:s0", "sys.pdp.action", "setupwizard_finish", 18);
	s9_patch_prop_file_one("u:object_r:default_prop:s0", "persist.sys.vzw_setup_running", "false", 5);
	s9_patch_prop_file_one("u:object_r:system_prop:s0", "persist.sys.vzw_setup_running", "false", 5);

	/* 9. Explicit patch for RIL, OMC, Bluetooth FW and Security props */
	{
		const char *prod_code = s9_ghost_get_prop("ril.product_code");
		const char *sec_policy = s9_ghost_get_prop("selinux.policy_version");
		const char *csc_ver = s9_ghost_get_prop("ril.official_cscver");
		const char *bt_fw = s9_ghost_get_prop("vendor.bluetooth_fw_ver");
		const char *sales_c = s9_ghost_get_prop("ro.csc.sales_code");

		if (prod_code && *prod_code) {
			s9_patch_prop_file_one("u:object_r:radio_prop:s0", "ril.product_code", prod_code, strlen(prod_code));
			s9_patch_prop_file_one("u:object_r:vendor_default_prop:s0", "vendor.ril.product_code", prod_code, strlen(prod_code));
		}
		if (sec_policy && *sec_policy) {
			s9_patch_prop_file_one("u:object_r:security_prop:s0", "selinux.policy_version", sec_policy, strlen(sec_policy));
		}
		if (csc_ver && *csc_ver) {
			s9_patch_prop_file_one("u:object_r:radio_prop:s0", "ril.official_cscver", csc_ver, strlen(csc_ver));
			s9_patch_prop_file_one("u:object_r:exported_config_prop:s0", "ro.omc.build.version", csc_ver, strlen(csc_ver));
		}
		if (bt_fw && *bt_fw) {
			s9_patch_prop_file_one("u:object_r:wifi_log_prop:s0", "vendor.bluetooth_fw_ver", bt_fw, strlen(bt_fw));
			s9_patch_prop_file_one("u:object_r:vendor_default_prop:s0", "vendor.bluetooth_fw_ver", bt_fw, strlen(bt_fw));
		}
		if (sales_c && *sales_c) {
			s9_patch_prop_file_one("u:object_r:audio_prop:s0", "persist.audio.sales_code", sales_c, strlen(sales_c));
			s9_patch_prop_file_one("u:object_r:exported2_default_prop:s0", "ro.boot.carrierid", sales_c, strlen(sales_c));
		}
		{
			const char *bb_ver = s9_ghost_get_prop("gsm.version.baseband");
			if (bb_ver && *bb_ver) {
				s9_patch_prop_file_one("u:object_r:radio_prop:s0", "gsm.version.baseband", bb_ver, strlen(bb_ver));
				s9_patch_prop_file_one("u:object_r:radio_prop:s0", "ril.sw_ver", bb_ver, strlen(bb_ver));
			}
		}
	}

	/* 10. Explicit patch for telephony / carrier / OMC properties */
	{
		static const char *const tele_keys[] = {
			"gsm.sim.state", "vendor.gsm.sim.state",
			"gsm.network.type", "vendor.gsm.network.type",
			"gsm.voice.network.type", "gsm.data.network.type",
			"gsm.operator.alpha", "gsm.sim.operator.alpha",
			"gsm.operator.numeric", "gsm.sim.operator.numeric",
			"gsm.sim.gsmoperator.numeric",
			"gsm.operator.iso-country", "gsm.sim.operator.iso-country",
			"gsm.operator.isroaming", "ril.simoperator",
			"persist.sys.sec_operator", "ril.rejectedPlmn",
			"ril.epdg.currenMno", "ril.wfc.default_spn",
			"ril.region_props", "ro.csc.sales_code",
			"ro.csc.omcnw_code", "ro.csc.omcnw_code2",
			"ro.csc.country_code", "ro.csc.countryiso_code",
			"ro.boot.carrierid", "persist.audio.sales_code",
			"persist.sys.omc_path", "persist.sys.omc_etcpath",
			"persist.sys.omc_respath", "persist.sys.omcnw_path",
			"persist.sys.omcnw_path2", "persist.sys.carrierid_etcpath",
			"persist.sys.timezone",
			"gsm.STK_SETUP_MENU", NULL
		};
		static const char *const tele_ctx[] = {
			"u:object_r:telephony_prop:s0",
			"u:object_r:radio_prop:s0",
			"u:object_r:exported_radio_prop:s0",
			"u:object_r:vendor_radio_prop:s0",
			"u:object_r:system_radio_prop:s0",
			"u:object_r:system_prop:s0",
			"u:object_r:exported2_default_prop:s0",
			"u:object_r:default_prop:s0",
			NULL
		};
		int k_idx, c_idx;
		for (k_idx = 0; tele_keys[k_idx]; k_idx++) {
			const char *v = s9_ghost_get_prop(tele_keys[k_idx]);
			if (v) {
				for (c_idx = 0; tele_ctx[c_idx]; c_idx++) {
					s9_patch_prop_file_one(tele_ctx[c_idx], tele_keys[k_idx], v, strlen(v));
				}
			}
		}
	}

	/* 11. Apply dynamic properties loaded from ghost.conf across all contexts. */
	if (s9_ghost_prop_count > 0) {
		for (ctx_idx = 0; s9_prop_contexts[ctx_idx]; ctx_idx++) {
			s9_patch_prop_context_batch(s9_prop_contexts[ctx_idx]);
		}
	}

	return 0;
}
EXPORT_SYMBOL(s9_ghost_patch_properties);

static void s9_hw_rtc_write_time(time64_t sec)
{
	struct rtc_device *rtc = rtc_class_open("rtc0");
	if (rtc) {
		struct rtc_time tm;
		rtc_time64_to_tm(sec, &tm);
		rtc_set_time(rtc, &tm);
		rtc_class_close(rtc);
	}
}

static void s9_sync_persistent_rtc(void)
{
	static const char *const rtc_paths[] = {
		"/efs/ghost_rtc.epoch",
		"/mnt/vendor/efs/ghost_rtc.epoch",
		NULL
	};
	struct timespec64 now;
	struct file *filp;
	char buf[32];
	ssize_t n;
	int i;

	getnstimeofday64(&now);
	/* 1735689600 = 2025-01-01 00:00:00 UTC */
	if (now.tv_sec < 1735689600LL) {
		for (i = 0; rtc_paths[i]; i++) {
			filp = filp_open(rtc_paths[i], O_RDONLY, 0);
			if (!IS_ERR(filp)) {
				n = kernel_read(filp, 0, buf, sizeof(buf) - 1);
				filp_close(filp, NULL);
				if (n > 0) {
					long long saved_sec = 0;
					buf[n] = '\0';
					if (!kstrtoll(strim(buf), 10, &saved_sec) &&
					    saved_sec >= 1735689600LL) {
						struct timespec64 ts;
						ts.tv_sec = (time64_t)(saved_sec + 3);
						ts.tv_nsec = 0;
						do_settimeofday64(&ts);
						s9_hw_rtc_write_time(ts.tv_sec);
						pr_info("S9GhostSerial: Restored system clock & RTC from %s to %lld\n",
							rtc_paths[i], (long long)ts.tv_sec);
						break;
					}
				}
			}
		}
	} else {
		s9_hw_rtc_write_time(now.tv_sec);
		for (i = 0; rtc_paths[i]; i++) {
			filp = filp_open(rtc_paths[i], O_WRONLY | O_CREAT | O_TRUNC, 0600);
			if (!IS_ERR(filp)) {
				int len = snprintf(buf, sizeof(buf), "%lld\n", (long long)now.tv_sec);
				kernel_write(filp, buf, len, 0);
				filp_close(filp, NULL);
				break;
			}
		}
	}
}

static void s9_optimize_boot_io(void)
{
	struct file *f = filp_open("/sys/block/sda/queue/read_ahead_kb", O_WRONLY, 0);
	if (!IS_ERR(f)) {
		kernel_write(f, "2048\n", 5, 0);
		filp_close(f, NULL);
	}
}

void s9_ghost_schedule_prop_sync(unsigned long delay_ms)
{
	if (READ_ONCE(s9_work_initialized))
		mod_delayed_work(system_wq, &s9_config_reload_work, msecs_to_jiffies(delay_ms));
}
EXPORT_SYMBOL(s9_ghost_schedule_prop_sync);

void s9_ghost_notify_boot_completed(void)
{
	WRITE_ONCE(s9_allow_crypto_cloak, true);
	s9_ghost_schedule_prop_sync(0);
}
EXPORT_SYMBOL(s9_ghost_notify_boot_completed);

static void s9_config_reload_work_fn(struct work_struct *work)
{
	static int passes = 0;
	passes++;

	/*
	 * Enable crypto state cloaking strictly after boot_completed == 1,
	 * ensuring init's on zygote-start and SystemServer User 0 unlock complete
	 * without waiting on vold encryption.
	 */
	if (s9_boot_completed)
		s9_allow_crypto_cloak = true;

	s9_sync_persistent_rtc();
	s9_optimize_boot_io();
	s9_load_config_file();
	s9_ghost_patch_properties();

	if (passes == 1)
		schedule_delayed_work(&s9_config_reload_work, msecs_to_jiffies(1500));
	else if (passes == 2)
		schedule_delayed_work(&s9_config_reload_work, msecs_to_jiffies(3000));
	else if (passes == 3)
		schedule_delayed_work(&s9_config_reload_work, msecs_to_jiffies(5000));
	else if (passes == 4)
		schedule_delayed_work(&s9_config_reload_work, msecs_to_jiffies(7000));
	else if (passes == 5)
		schedule_delayed_work(&s9_config_reload_work, msecs_to_jiffies(10000));
	else if (passes == 6)
		schedule_delayed_work(&s9_config_reload_work, msecs_to_jiffies(15000));
	else
		schedule_delayed_work(&s9_config_reload_work, msecs_to_jiffies(15000));
}

/*
 * Procfs control node: /proc/s9_serial (root write-only 0200, silent read)
 */
static int s9_serial_proc_show(struct seq_file *m, void *v)
{
	return 0;
}

static int s9_serial_proc_open(struct inode *inode, struct file *file)
{
	kuid_t uid = current_uid();
	if (uid.val != 0)
		return -ENOENT;
	return single_open(file, s9_serial_proc_show, NULL);
}

static ssize_t s9_serial_proc_write(struct file *file, const char __user *buf,
				    size_t count, loff_t *pos)
{
	char kcmd[32];
	size_t len = min(count, sizeof(kcmd) - 1);
	kuid_t uid = current_uid();

	if (uid.val != 0)
		return -ENOENT;

	if (copy_from_user(kcmd, buf, len))
		return -EFAULT;
	kcmd[len] = '\0';

	if (strstr(kcmd, "reload") || strstr(kcmd, "sync") || strstr(kcmd, "1")) {
		s9_allow_crypto_cloak = true;
		mod_delayed_work(system_wq, &s9_config_reload_work, 0);
		flush_delayed_work(&s9_config_reload_work);
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

bool s9_ghost_get_drm_id_bytes(u8 *out, size_t len)
{
	unsigned long flags;
	s9_ensure_init();
	if (!out || len < 32)
		return false;
	spin_lock_irqsave(&s9_serial_lock, flags);
	if (!s9_active_serial_prof.has_drm_id) {
		spin_unlock_irqrestore(&s9_serial_lock, flags);
		return false;
	}
	memcpy(out, s9_active_serial_prof.drm_id_bytes, 32);
	spin_unlock_irqrestore(&s9_serial_lock, flags);
	return true;
}
EXPORT_SYMBOL(s9_ghost_get_drm_id_bytes);

bool s9_ghost_get_drm_id_hex(char *out, size_t len)
{
	unsigned long flags;
	s9_ensure_init();
	if (!out || len < 65)
		return false;
	spin_lock_irqsave(&s9_serial_lock, flags);
	if (!s9_active_serial_prof.has_drm_id) {
		spin_unlock_irqrestore(&s9_serial_lock, flags);
		return false;
	}
	strlcpy(out, s9_active_serial_prof.drm_id_hex, len);
	spin_unlock_irqrestore(&s9_serial_lock, flags);
	return true;
}
EXPORT_SYMBOL(s9_ghost_get_drm_id_hex);

bool s9_ghost_get_ril_barcode(char *out, size_t len)
{
	unsigned long flags;
	s9_ensure_init();
	if (!out || len == 0)
		return false;
	spin_lock_irqsave(&s9_serial_lock, flags);
	strlcpy(out, s9_active_serial_prof.ril_barcode, len);
	spin_unlock_irqrestore(&s9_serial_lock, flags);
	return true;
}
EXPORT_SYMBOL(s9_ghost_get_ril_barcode);

static int __init s9_ghost_serial_late_init(void)
{
	s9_ensure_init();
	proc_create("s9_serial", 0200, NULL, &s9_serial_proc_fops);

	INIT_DELAYED_WORK(&s9_config_reload_work, s9_config_reload_work_fn);
	WRITE_ONCE(s9_work_initialized, true);
	/* Initial property & RTC sync at 1 second, followed by progressive passes */
	schedule_delayed_work(&s9_config_reload_work, msecs_to_jiffies(1000));
	return 0;
}
late_initcall(s9_ghost_serial_late_init);

static int __init s9_ghost_serial_core_init(void)
{
	s9_ghost_serial_init();
	return 0;
}
core_initcall(s9_ghost_serial_core_init);

MODULE_DESCRIPTION("Samsung Galaxy S9 Pure Kernel Serial Number & Profile Virtualizer");
MODULE_AUTHOR("khiconjk");
MODULE_LICENSE("GPL v2");
