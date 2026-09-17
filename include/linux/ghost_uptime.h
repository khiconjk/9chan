#ifndef _LINUX_GHOST_UPTIME_H
#define _LINUX_GHOST_UPTIME_H

#include <linux/types.h>
#include <linux/time.h>

struct timekeeper;

extern u64 s9_ghost_uptime_offset_sec;
extern u64 s9_ghost_uptime_offset_ns;
extern u64 s9_ghost_mono_offset_sec;
extern u64 s9_ghost_mono_offset_ns;
extern struct kobject *pwr_stats_kobj;

void s9_ghost_uptime_init(u64 rtc_sec);
void s9_ghost_uptime_apply_boot_offset(struct timekeeper *tk);
u64 s9_ghost_uptime_get_sec(void);
u64 s9_ghost_uptime_get_ns(void);

#endif /* _LINUX_GHOST_UPTIME_H */
