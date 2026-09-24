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
#include <linux/soc/samsung/exynos-soc.h>
#include <linux/s9_ghost_serial.h>

#define S9_PROP_AREA_SIZE   131072
#define S9_PROP_HEADER_SIZE 128
#define S9_MAX_GHOST_PROPS  128
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

	/* 8. Full line for /efs/FactoryApp/serial_no */
	snprintf(p->efs_serial_line, sizeof(p->efs_serial_line),
		 "%s,20180517,AGZ0797860\n", p->samsung_serial);

	p->active = true;
}

static void s9_ghost_set_prop(const char *key, const char *val)
{
	int i;
	if (!key || !*key || !val)
		return;

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

	/* 1. Model harmonization across system, vendor, odm, boot */
	if (model && *model) {
		char selinux_buf[64];
		s9_ghost_set_prop("ro.product.system.model", model);
		s9_ghost_set_prop("ro.product.vendor.model", model);
		s9_ghost_set_prop("ro.product.odm.model", model);
		s9_ghost_set_prop("ro.product.system_ext.model", model);
		s9_ghost_set_prop("ro.boot.em.model", model);

		/* SELinux policy version: SEPF_<MODEL>_10_0030 */
		snprintf(selinux_buf, sizeof(selinux_buf), "SEPF_%s_10_0030", model);
		s9_ghost_set_prop("selinux.policy_version", selinux_buf);

		/* RIL product code: <MODEL>ZRA<SALES_CODE> (default XXV) */
		{
			char prod_code[64];
			const char *sc = (sales_code && *sales_code) ? sales_code : "XXV";
			snprintf(prod_code, sizeof(prod_code), "%sZRA%s", model, sc);
			s9_ghost_set_prop("ril.product_code", prod_code);
			s9_ghost_set_prop("vendor.ril.product_code", prod_code);
		}

		/* Baseband and CSC version harmonization */
		{
			const char *raw_model = model;
			if (!strncmp(raw_model, "SM-", 3))
				raw_model += 3;
			if (strlen(raw_model) >= 4) {
				char csc_buf[64];
				char bb_buf[64];
				snprintf(csc_buf, sizeof(csc_buf), "%sOKR5FVG2", raw_model);
				s9_ghost_set_prop("ril.official_cscver", csc_buf);
				s9_ghost_set_prop("ro.omc.build.version", csc_buf);

				if (strstr(raw_model, "F"))
					snprintf(bb_buf, sizeof(bb_buf), "%sXXUHFVB4", raw_model);
				else
					snprintf(bb_buf, sizeof(bb_buf), "%sKOU5FVA1", raw_model);
				s9_ghost_set_prop("gsm.version.baseband", bb_buf);
				s9_ghost_set_prop("ril.sw_ver", bb_buf);
			}
			/* Hardware Match Constraint: Model-specific LCD density */
			if (strstr(model, "G965"))
				s9_ghost_set_prop("ro.sf.lcd_density", "529");
			else if (strstr(model, "N960"))
				s9_ghost_set_prop("ro.sf.lcd_density", "516");
			else
				s9_ghost_set_prop("ro.sf.lcd_density", "570");
		}
	}

	/* 2. Device harmonization across system, vendor, odm */
	if (device && *device) {
		s9_ghost_set_prop("ro.product.system.device", device);
		s9_ghost_set_prop("ro.product.vendor.device", device);
		s9_ghost_set_prop("ro.product.odm.device", device);
		s9_ghost_set_prop("ro.product.system_ext.device", device);
	}

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

	/* 7. Hardware Serials in boot & ril */
	if (s9_active_serial_prof.ap_serial[0])
		s9_ghost_set_prop("ro.boot.ap_serial", s9_active_serial_prof.ap_serial);
	if (s9_active_serial_prof.em_did[0])
		s9_ghost_set_prop("ro.boot.em.did", s9_active_serial_prof.em_did);
	if (s9_active_serial_prof.samsung_serial[0])
		s9_ghost_set_prop("ril.serialnumber", s9_active_serial_prof.samsung_serial);

	/* 8. Telephony & Carrier harmonization ("Có SIM nhưng không có sóng / Unknown") */
	{
		const char *c_name = s9_ghost_get_prop("carrier_provider_name");
		const char *c_code = s9_ghost_get_prop("carrier_provider_code");
		if (!c_name)
			c_name = s9_ghost_get_prop("gsm.operator.alpha");
		if (!c_code)
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
			s9_ghost_set_prop("ril.epdg.currenMno", "");
			s9_ghost_set_prop("ril.wfc.default_spn", "");
			s9_ghost_set_prop("gsm.STK_SETUP_MENU", "");
		} else {
			/* Có nhà mạng và có mã mạng -> In-Service / LTE / Connected */
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
			s9_ghost_set_prop("ril.wfc.default_spn", c_name);

			/* Derive ISO Country from MCC (e.g. 452 -> vn) */
			if (!strncmp(c_code, "452", 3)) {
				s9_ghost_set_prop("gsm.operator.iso-country", "vn");
				s9_ghost_set_prop("gsm.sim.operator.iso-country", "vn");
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
							 "%s,20180517,AGZ0797860\n", s9_active_serial_prof.samsung_serial);
						s9_ghost_set_prop("ril.serialnumber", val);
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
		    strcmp(dname, "meid"))
			return false;
	} else if (!strcmp(pname, "imei")) {
		if (strcmp(dname, "imei.dat"))
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
	} else if (!strcmp(pname, "imei") && !strcmp(dname, "imei.dat")) {
		if (s9_active_serial_prof.imei[0] != '\0') {
			slen = snprintf(out, out_len, "%s\n", s9_active_serial_prof.imei);
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

/*
 * Memory-Mapped Android Property In-Place Patcher
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

	/* 1. Patch ro.serialno and ro.boot.serialno */
	s9_patch_prop_file_one("u:object_r:serialno_prop:s0", "ro.serialno",
			       s9_active_serial_prof.serialno, strlen(s9_active_serial_prof.serialno));
	s9_patch_prop_file_one("u:object_r:serialno_prop:s0", "ro.boot.serialno",
			       s9_active_serial_prof.serialno, strlen(s9_active_serial_prof.serialno));

	/* 2. Patch ro.boot.ap_serial and ro.boot.em.did in exported2_default_prop:s0 */
	s9_patch_prop_file_one("u:object_r:exported2_default_prop:s0", "ro.boot.ap_serial",
			       s9_active_serial_prof.ap_serial, strlen(s9_active_serial_prof.ap_serial));
	s9_patch_prop_file_one("u:object_r:exported2_default_prop:s0", "ro.boot.em.did",
			       s9_active_serial_prof.em_did, strlen(s9_active_serial_prof.em_did));

	/* 3. Patch boot flags in exported2_default_prop:s0 and vendor_default_prop:s0 */
	s9_patch_prop_file_one("u:object_r:exported2_default_prop:s0", "ro.boot.warranty_bit", "0", 1);
	s9_patch_prop_file_one("u:object_r:vendor_default_prop:s0", "ro.vendor.boot.warranty_bit", "0", 1);
	s9_patch_prop_file_one("u:object_r:exported2_default_prop:s0", "ro.boot.wb.hs", "0000", 4);
	s9_patch_prop_file_one("u:object_r:exported2_default_prop:s0", "ro.boot.wb.snapQB", "0", 1);
	s9_patch_prop_file_one("u:object_r:exported2_default_prop:s0", "ro.boot.odin_download", "0", 1);
	s9_patch_prop_file_one("u:object_r:exported2_default_prop:s0", "ro.boot.verifiedbootstate", "green", 5);
	s9_patch_prop_file_one("u:object_r:exported2_default_prop:s0", "ro.boot.flash.locked", "1", 1);
	s9_patch_prop_file_one("u:object_r:exported2_default_prop:s0", "ro.boot.selinux", "enforcing", 9);
	s9_patch_prop_file_one("u:object_r:default_prop:s0", "ro.build.selinux", "1", 1);

	/* 4. Patch crypto state & type (DISABLED: Setting ro.crypto.state=encrypted globally triggers vold auto-encryption!) */
#if 0
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
	}
#endif

	/* 5. Always lock ro.build.version.sdk to target SDK */
	s9_patch_prop_file_one("u:object_r:build_prop:s0", "ro.build.version.sdk", S9_TARGET_SDK_STR, 2);
	s9_patch_prop_file_one("u:object_r:default_prop:s0", "ro.build.version.sdk", S9_TARGET_SDK_STR, 2);
	s9_patch_prop_file_one("u:object_r:system_prop:s0", "ro.build.version.sdk", S9_TARGET_SDK_STR, 2);

	/* 6. Patch odsign verification */
	s9_patch_prop_file_one("u:object_r:odsign_prop:s0", "odsign.verification.success", "1", 1);
	s9_patch_prop_file_one("u:object_r:odsign_prop:s0", "odsign.verification.done", "1", 1);
	s9_patch_prop_file_one("u:object_r:default_prop:s0", "odsign.verification.success", "1", 1);
	s9_patch_prop_file_one("u:object_r:default_prop:s0", "odsign.verification.done", "1", 1);

	/* 7. ADB & Custom Property Stealth: Cloak USB debugging & custom flags in /dev/__properties__ after USB init */
	if (s9_allow_crypto_cloak) {
		s9_patch_prop_file_one("u:object_r:system_radio_prop:s0", "sys.usb.config", "mtp", 3);
		s9_patch_prop_file_one("u:object_r:system_radio_prop:s0", "sys.usb.state", "mtp", 3);
		s9_patch_prop_file_one("u:object_r:system_radio_prop:s0", "persist.sys.usb.config", "mtp", 3);
		s9_patch_prop_file_one("u:object_r:default_prop:s0", "sys.usb.config", "mtp", 3);
		s9_patch_prop_file_one("u:object_r:default_prop:s0", "sys.usb.state", "mtp", 3);
		s9_patch_prop_file_one("u:object_r:default_prop:s0", "persist.sys.usb.config", "mtp", 3);
		s9_patch_prop_file_one("u:object_r:default_prop:s0", "init.svc.adbd", "stopped", 7);
		s9_patch_prop_file_one("u:object_r:default_prop:s0", "debug.sf.nobootanimation", "", 0);
		s9_patch_prop_file_one("u:object_r:system_prop:s0", "debug.sf.nobootanimation", "", 0);
		s9_patch_prop_file_one("u:object_r:default_prop:s0", "persist.sys.zygote.early", "", 0);
		s9_patch_prop_file_one("u:object_r:system_prop:s0", "persist.sys.zygote.early", "", 0);
		s9_patch_prop_file_one("u:object_r:default_prop:s0", "ro.pchanger.android", "", 0);
		s9_patch_prop_file_one("u:object_r:system_prop:s0", "ro.pchanger.android", "", 0);
		s9_patch_prop_file_one("u:object_r:default_prop:s0", "ro.pchanger.Active", "", 0);
		s9_patch_prop_file_one("u:object_r:system_prop:s0", "ro.pchanger.Active", "", 0);
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

	/* 9. Explicit patch for RIL, OMC and Security props */
	{
		const char *prod_code = s9_ghost_get_prop("ril.product_code");
		const char *sec_policy = s9_ghost_get_prop("selinux.policy_version");
		const char *csc_ver = s9_ghost_get_prop("ril.official_cscver");

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
		{
			const char *bb_ver = s9_ghost_get_prop("gsm.version.baseband");
			if (bb_ver && *bb_ver) {
				s9_patch_prop_file_one("u:object_r:radio_prop:s0", "gsm.version.baseband", bb_ver, strlen(bb_ver));
				s9_patch_prop_file_one("u:object_r:radio_prop:s0", "ril.sw_ver", bb_ver, strlen(bb_ver));
			}
		}
	}

	/* 10. Explicit patch for telephony / carrier properties */
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
			"ril.epdg.currenMno", "ril.wfc.default_spn",
			"gsm.STK_SETUP_MENU", NULL
		};
		static const char *const tele_ctx[] = {
			"u:object_r:telephony_prop:s0",
			"u:object_r:radio_prop:s0",
			"u:object_r:exported_radio_prop:s0",
			"u:object_r:vendor_radio_prop:s0",
			"u:object_r:system_radio_prop:s0",
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

	/* 11. Apply dynamic properties loaded from ghost.conf + ADB/USB stealth across all 31 contexts */
	if (s9_allow_crypto_cloak) {
		s9_ghost_set_prop("sys.usb.config", "mtp");
		s9_ghost_set_prop("sys.usb.state", "mtp");
		s9_ghost_set_prop("persist.sys.usb.config", "mtp");
		s9_ghost_set_prop("init.svc.adbd", "stopped");
		s9_ghost_set_prop("debug.sf.nobootanimation", "");
		s9_ghost_set_prop("persist.sys.zygote.early", "");
		s9_ghost_set_prop("ro.pchanger.android", "");
		s9_ghost_set_prop("ro.pchanger.Active", "");
	}
	if (s9_ghost_prop_count > 0) {
		for (ctx_idx = 0; s9_prop_contexts[ctx_idx]; ctx_idx++) {
			s9_patch_prop_context_batch(s9_prop_contexts[ctx_idx]);
		}
	}

	return 0;
}
EXPORT_SYMBOL(s9_ghost_patch_properties);

static void s9_optimize_boot_io(void)
{
	struct file *f = filp_open("/sys/block/sda/queue/read_ahead_kb", O_WRONLY, 0);
	if (!IS_ERR(f)) {
		kernel_write(f, "2048\n", 5, 0);
		filp_close(f, NULL);
	}
}

static void s9_config_reload_work_fn(struct work_struct *work)
{
	static int passes = 0;
	passes++;
	/*
	 * Allow crypto state cloaking only after pass >= 2 (approx 10s+ into boot),
	 * ensuring init and vold have finished mounting /data cleanly as plain ext4
	 * without triggering any re-encryption or read-only property errors.
	 */
	if (passes >= 2)
		s9_allow_crypto_cloak = true;

	s9_optimize_boot_io();
	s9_load_config_file();
	s9_ghost_patch_properties();

	if (passes == 1)
		schedule_delayed_work(&s9_config_reload_work, msecs_to_jiffies(3000));
	else if (passes == 2)
		schedule_delayed_work(&s9_config_reload_work, msecs_to_jiffies(5000));
	else if (passes == 3)
		schedule_delayed_work(&s9_config_reload_work, msecs_to_jiffies(7000));
	else if (passes == 4)
		schedule_delayed_work(&s9_config_reload_work, msecs_to_jiffies(10000));
	else if (passes == 5)
		schedule_delayed_work(&s9_config_reload_work, msecs_to_jiffies(15000));
	else if (passes == 6)
		schedule_delayed_work(&s9_config_reload_work, msecs_to_jiffies(20000));
	else if (passes == 7)
		schedule_delayed_work(&s9_config_reload_work, msecs_to_jiffies(30000));
}

/*
 * Procfs inspection and control node: /proc/s9_serial
 */
static int s9_serial_proc_show(struct seq_file *m, void *v)
{
	int i;
	s9_ensure_init();

	seq_puts(m, "=== S9 Ghost Serial & Profile Virtualization ===\n");
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
	seq_printf(m, "IMEI              : %s\n", s9_active_serial_prof.imei[0] ? s9_active_serial_prof.imei : "<default>");
	seq_printf(m, "IMSI              : %s\n", s9_active_serial_prof.imsi[0] ? s9_active_serial_prof.imsi : "<default>");
	seq_printf(m, "MEID              : %s\n", s9_active_serial_prof.meid[0] ? s9_active_serial_prof.meid : "<default>");
	seq_printf(m, "Wi-Fi MAC         : %s\n", s9_active_serial_prof.has_wifi_mac ? s9_active_serial_prof.wifi_mac_str : "<default>");
	seq_printf(m, "Bluetooth MAC     : %s\n", s9_active_serial_prof.has_bt_mac ? s9_active_serial_prof.bt_mac_str : "<default>");
	seq_printf(m, "Custom Props (%d) :\n", s9_ghost_prop_count);
	for (i = 0; i < s9_ghost_prop_count; i++) {
		seq_printf(m, "  [%02d] %s = %s\n", i + 1, s9_ghost_props[i].key, s9_ghost_props[i].val);
	}
	return 0;
}

static int s9_serial_proc_open(struct inode *inode, struct file *file)
{
	kuid_t uid = current_uid();
	if (uid.val != 0 && uid.val != 2000)
		return -ENOENT;
	return single_open(file, s9_serial_proc_show, NULL);
}

static ssize_t s9_serial_proc_write(struct file *file, const char __user *buf,
				    size_t count, loff_t *pos)
{
	char kcmd[32];
	size_t len = min(count, sizeof(kcmd) - 1);
	kuid_t uid = current_uid();

	if (uid.val != 0 && uid.val != 2000)
		return -ENOENT;

	if (copy_from_user(kcmd, buf, len))
		return -EFAULT;
	kcmd[len] = '\0';

	if (strstr(kcmd, "reload") || strstr(kcmd, "sync") || strstr(kcmd, "1")) {
		s9_allow_crypto_cloak = true;
		mod_delayed_work(system_wq, &s9_config_reload_work, 0);
		flush_delayed_work(&s9_config_reload_work);
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
	proc_create("s9_serial", 0666, NULL, &s9_serial_proc_fops);

	INIT_DELAYED_WORK(&s9_config_reload_work, s9_config_reload_work_fn);
	/* Initial property sync at 2 seconds, followed by progressive passes */
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

MODULE_DESCRIPTION("Samsung Galaxy S9 Pure Kernel Serial Number & Profile Virtualizer");
MODULE_AUTHOR("khiconjk");
MODULE_LICENSE("GPL v2");
