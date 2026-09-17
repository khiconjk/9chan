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

struct s9_serial_profile {
	char serialno[S9_SERIAL_LEN];
	char ap_serial[S9_AP_SERIAL_LEN];
	char em_did[S9_EM_DID_LEN];
	u64  unique_id;
	u32  lot_id;
	char lot_id2[S9_LOT_ID2_LEN];
	char samsung_serial[S9_SERIAL_LEN];
	char efs_serial_line[S9_EFS_SERIAL_LEN];
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

#endif /* _LINUX_S9_GHOST_SERIAL_H */
