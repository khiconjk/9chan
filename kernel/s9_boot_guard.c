/*
 * Samsung Galaxy S9 (starlte) Boot Guard Suite
 * Anti-Bootloop & Automatic Recovery Rescue
 * Simplified Version: system_server crash monitor only (no blind timed watchdog)
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/workqueue.h>
#include <linux/reboot.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>
#include <linux/string.h>
#include <linux/s9_boot_guard.h>
#include <linux/ghost_uptime.h>

int s9_boot_completed = 0;
EXPORT_SYMBOL(s9_boot_completed);

static int s9_system_server_crash_count = 0;
static struct work_struct s9_recovery_reboot_work;

static void s9_recovery_reboot_fn(struct work_struct *work)
{
	pr_emerg("S9_BOOT_GUARD: Executing rescue reboot into TWRP Recovery...\n");
	emergency_restart();
}

void s9_boot_guard_mark_completed(const char *reason)
{
	if (!s9_boot_completed) {
		s9_boot_completed = 1;
		pr_info("S9_BOOT_GUARD: Boot completed successfully (%s).\n",
			reason ? reason : "unknown");
	}
}
EXPORT_SYMBOL(s9_boot_guard_mark_completed);

void s9_check_bootloop_crash(const char *comm, int exit_code)
{
	if (s9_boot_completed || !comm)
		return;

	if (strcmp(comm, "system_server") == 0) {
		s9_system_server_crash_count++;
		pr_emerg("S9_BOOT_GUARD: system_server died during early boot (crash count: %d, code: %d)\n",
			 s9_system_server_crash_count, exit_code);

		if (s9_system_server_crash_count >= 2) {
			pr_emerg("S9_BOOT_GUARD: Repeated system_server crashes detected (>= 2)! Rebooting to TWRP Recovery...\n");
			schedule_work(&s9_recovery_reboot_work);
		}
	}
}
EXPORT_SYMBOL(s9_check_bootloop_crash);

/* Sysfs interface: /sys/kernel/power_stats/boot_completed */
static ssize_t boot_completed_show(struct kobject *kobj,
				   struct kobj_attribute *attr,
				   char *buf)
{
	return sprintf(buf, "%d\n", s9_boot_completed);
}

static ssize_t boot_completed_store(struct kobject *kobj,
				    struct kobj_attribute *attr,
				    const char *buf, size_t count)
{
	int val = 0;
	if (kstrtoint(buf, 10, &val) == 0 && val == 1) {
		s9_boot_guard_mark_completed("sysfs write");
	}
	return count;
}

static struct kobj_attribute boot_completed_attr =
	__ATTR(boot_completed, 0644, boot_completed_show, boot_completed_store);

static int __init s9_boot_guard_sysfs_init(void)
{
	if (pwr_stats_kobj) {
		int err = sysfs_create_file(pwr_stats_kobj, &boot_completed_attr.attr);
		if (err)
			pr_warn("S9_BOOT_GUARD: Failed to create sysfs file: %d\n", err);
	}
	return 0;
}
late_initcall_sync(s9_boot_guard_sysfs_init);

static int __init s9_boot_guard_init(void)
{
	INIT_WORK(&s9_recovery_reboot_work, s9_recovery_reboot_fn);
	pr_info("S9_BOOT_GUARD: Anti-bootloop active (monitoring system_server, threshold=2 crashes -> TWRP)\n");
	return 0;
}
late_initcall(s9_boot_guard_init);
