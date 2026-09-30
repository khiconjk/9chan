#ifndef _LINUX_S9_GHOST_SERIAL_H
#define _LINUX_S9_GHOST_SERIAL_H

#include <linux/types.h>
#include <linux/path.h>
#include <linux/fs.h>

#define S9_SERIAL_LEN       32
#define S9_AP_SERIAL_LEN    24
#define S9_EM_DID_LEN       24
#define S9_LOT_ID2_LEN      8
#define S9_EFS_SERIAL_LEN   64
#define S9_IMEI_LEN         32
#define S9_IMSI_LEN         32
#define S9_MAC_LEN          32

struct s9_serial_profile {
	char serialno[S9_SERIAL_LEN];
	char ap_serial[S9_AP_SERIAL_LEN];
	char em_did[S9_EM_DID_LEN];
	u64  unique_id;
	u32  lot_id;
	char lot_id2[S9_LOT_ID2_LEN];
	char samsung_serial[S9_SERIAL_LEN];
	char efs_serial_line[S9_EFS_SERIAL_LEN];
	char imei[S9_IMEI_LEN];
	char imsi[S9_IMSI_LEN];
	char meid[S9_IMEI_LEN];
	char wifi_mac_str[S9_MAC_LEN];
	u8   wifi_mac_bytes[6];
	bool has_wifi_mac;
	char bt_mac_str[S9_MAC_LEN];
	bool has_bt_mac;
	char wifi_bssid_str[S9_MAC_LEN];
	u8   wifi_bssid_bytes[6];
	bool has_wifi_bssid;
	char wifi_arp_mac_str[S9_MAC_LEN];
	u8   wifi_arp_mac_bytes[6];
	char wifi_ssid_str[64];
	char wifi_ssid7_str[8];
	bool has_wifi_ssid;
	u8   wifi_ip_octet;
	char wifi_ip_octet_str[4];
	char ril_barcode[S9_SERIAL_LEN];
	char ril_mfg_date[16];
	char ril_rfcal_date[16];
	char drm_id_hex[65];
	u8   drm_id_bytes[32];
	bool has_drm_id;
	char emmc_cid[36];
	bool has_emmc_cid;
	char emmc_serial[16];
	char emmc_name[16];
	char emmc_manfid[16];
	char emmc_oemid[16];
	char emmc_date[16];
	char ufs_serial[16];
	u8   ufs_vpd_pg80[16];
	size_t ufs_vpd_pg80_len;
	char ufs_wwid[32];
	bool has_ufs_wwid;
	bool active;
};

#define FMODE_GHOST_MMC_CID     ((__force fmode_t)0x01000000)
#define FMODE_GHOST_MMC_SER     ((__force fmode_t)0x02000000)
#define FMODE_GHOST_MMC_NAME    ((__force fmode_t)0x10000000)
#define FMODE_GHOST_MMC_MANFID  ((__force fmode_t)0x20000000)
#define FMODE_GHOST_MMC_OEMID   ((__force fmode_t)0x40000000)
#define FMODE_GHOST_MMC_DATE    ((__force fmode_t)0x80000000)
#define FMODE_GHOST_MMC_MASK    (FMODE_GHOST_MMC_CID | FMODE_GHOST_MMC_SER | \
                                 FMODE_GHOST_MMC_NAME | FMODE_GHOST_MMC_MANFID | \
                                 FMODE_GHOST_MMC_OEMID | FMODE_GHOST_MMC_DATE)

void s9_ghost_serial_init(void);
void s9_ghost_sanitize_cmdline(char *cmd, size_t max_len);
void s9_ghost_sanitize_bootargs_buffer(char *buf, size_t len);
void s9_ghost_sync_chipid(u64 *p_unique_id, u32 *p_lot_id, char *lot_id2);
void s9_ghost_get_active_serial(char *out, size_t len);
bool s9_ghost_get_ap_serial(char *out, size_t len);
bool s9_ghost_get_samsung_serial(char *out, size_t len);
bool s9_ghost_get_lot_id2(char *out, size_t len);
bool s9_ghost_is_cloaked_efs_path(const struct path *path);
bool s9_ghost_get_cloaked_efs_payload(const char *dname, const char *pname,
				      char *out, size_t out_len, size_t *out_plen);
ssize_t s9_ghost_vfs_inject_string(char __user *buf, size_t count, loff_t *pos,
				   const char *src, size_t src_len);
bool s9_ghost_is_cloaked_storage_path(const struct path *path);
bool s9_ghost_get_cloaked_storage_payload(const char *dname, const char *pname,
					  char *out, size_t out_len, size_t *out_plen);
bool s9_ghost_is_virtual_mmc_path(const char *pathname);
fmode_t s9_ghost_get_virtual_mmc_fmode(const char *pathname);
bool s9_ghost_get_virtual_mmc_payload(const char *pathname, char *out, size_t out_len, size_t *out_plen);
bool s9_ghost_get_virtual_mmc_payload_by_mode(fmode_t mode, char *out, size_t out_len, size_t *out_plen);
int s9_ghost_patch_properties(void);
void s9_ghost_notify_boot_completed(void);
void s9_ghost_schedule_prop_sync(unsigned long delay_ms);
bool s9_ghost_get_wifi_mac_bytes(unsigned char *buf);
bool s9_ghost_get_wifi_bssid_str(char *out, size_t len);
bool s9_ghost_get_wifi_bssid_bytes(unsigned char *buf);
bool s9_ghost_get_wifi_arp_mac_str(char *out, size_t len);
bool s9_ghost_get_wifi_arp_mac_bytes(unsigned char *buf);
void s9_ghost_set_real_wifi_bssid(const u8 *bssid);
bool s9_ghost_get_real_wifi_bssid(u8 *out);
bool s9_ghost_is_real_wifi_bssid(const u8 *bssid);
bool s9_ghost_get_wifi_ssid7_str(char *out, size_t len);
u8   s9_ghost_get_wifi_ip_octet(void);
__be32 s9_ghost_cloak_wlan_ipv4(__be32 addr);
bool s9_ghost_get_drm_id_bytes(u8 *out, size_t len);
bool s9_ghost_get_drm_id_hex(char *out, size_t len);
bool s9_ghost_get_ril_barcode(char *out, size_t len);
void s9_ghost_gnss_set_enabled(int enabled);
void s9_ghost_gnss_set_lat_str(const char *lat_str);
void s9_ghost_gnss_set_lon_str(const char *lon_str);
void s9_ghost_gnss_set_alt_str(const char *alt_str);

#ifndef S9_TARGET_SDK_STR
#if defined(CONFIG_S9_TARGET_SDK_STR)
#define S9_TARGET_SDK_STR CONFIG_S9_TARGET_SDK_STR
#elif defined(ANDROID_VERSION) && (ANDROID_VERSION < 110000)
#define S9_TARGET_SDK_STR "29"
#elif defined(ANDROID_VERSION) && (ANDROID_VERSION < 130000)
#define S9_TARGET_SDK_STR "32"
#else
#define S9_TARGET_SDK_STR "29"
#endif
#endif

#ifndef S9_CRYPTO_TYPE_STR
#if defined(ANDROID_VERSION) && (ANDROID_VERSION < 110000)
#define S9_CRYPTO_TYPE_STR "block"
#else
#define S9_CRYPTO_TYPE_STR "file"
#endif
#endif

#endif /* _LINUX_S9_GHOST_SERIAL_H */
