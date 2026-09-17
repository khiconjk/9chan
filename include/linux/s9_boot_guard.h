#ifndef _LINUX_S9_BOOT_GUARD_H
#define _LINUX_S9_BOOT_GUARD_H

extern int s9_boot_completed;

void s9_boot_guard_mark_completed(const char *reason);
void s9_check_bootloop_crash(const char *comm, int exit_code);

#endif /* _LINUX_S9_BOOT_GUARD_H */
