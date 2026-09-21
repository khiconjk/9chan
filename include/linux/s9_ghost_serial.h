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
	bool active;
};

void s9_ghost_serial_init(void);
void s9_ghost_sanitize_cmdline(char *cmd, size_t max_len);
void s9_ghost_sanitize_bootargs_buffer(char *buf, size_t len);
void s9_ghost_sync_chipid(u64 *p_unique_id, u32 *p_lot_id, char *lot_id2);
void s9_ghost_get_active_serial(char *out, size_t len);
bool s9_ghost_is_cloaked_efs_path(const struct path *path);
bool s9_ghost_get_cloaked_efs_payload(const char *dname, const char *pname,
				      char *out, size_t out_len, size_t *out_plen);
ssize_t s9_ghost_vfs_inject_string(char __user *buf, size_t count, loff_t *pos,
				   const char *src, size_t src_len);
int s9_ghost_patch_properties(void);
bool s9_ghost_get_wifi_mac_bytes(unsigned char *buf);
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
