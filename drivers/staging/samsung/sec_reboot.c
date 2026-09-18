/*
 * Copyright (c) 2014 Samsung Electronics Co., Ltd.
 *      http://www.samsung.com
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */

#include <linux/delay.h>
#include <linux/pm.h>
#include <linux/io.h>
#include <linux/gpio.h>
#ifdef CONFIG_OF
#include <linux/of.h>
#include <linux/of_gpio.h>
#include <linux/input.h>
#endif
#include <linux/sec_ext.h>
#include "../../battery_v2/include/sec_battery.h"
#include <linux/sec_batt.h>

#include <asm/cacheflush.h>
#include <asm/system_misc.h>

#include <soc/samsung/exynos-pmu.h>
#include <soc/samsung/acpm_ipc_ctrl.h>

#if defined(CONFIG_SEC_ABC)
#include <linux/sti/abc_common.h>
#endif

/* function ptr for original arm_pm_restart */
void (*mach_restart)(enum reboot_mode mode, const char *cmd);
EXPORT_SYMBOL(mach_restart);

/* INFORM2 */
enum sec_power_flags {
	SEC_POWER_OFF = 0x0,
	SEC_POWER_RESET = 0x12345678,
};
/* INFORM3 */
#define SEC_RESET_REASON_PREFIX 0x12345670
#define SEC_RESET_SET_PREFIX    0xabc00000
enum sec_reset_reason {
	SEC_RESET_REASON_UNKNOWN   = (SEC_RESET_REASON_PREFIX | 0x0),
	SEC_RESET_REASON_DOWNLOAD  = (SEC_RESET_REASON_PREFIX | 0x1),
	SEC_RESET_REASON_UPLOAD    = (SEC_RESET_REASON_PREFIX | 0x2),
	SEC_RESET_REASON_CHARGING  = (SEC_RESET_REASON_PREFIX | 0x3),
	SEC_RESET_REASON_RECOVERY  = (SEC_RESET_REASON_PREFIX | 0x4),
	SEC_RESET_REASON_FOTA      = (SEC_RESET_REASON_PREFIX | 0x5),
	SEC_RESET_REASON_FOTA_BL   = (SEC_RESET_REASON_PREFIX | 0x6), /* update bootloader */
	SEC_RESET_REASON_SECURE    = (SEC_RESET_REASON_PREFIX | 0x7), /* image secure check fail */
	SEC_RESET_REASON_FWUP      = (SEC_RESET_REASON_PREFIX | 0x9), /* emergency firmware update */
	SEC_RESET_REASON_EM_FUSE   = (SEC_RESET_REASON_PREFIX | 0xa), /* EMC market fuse */
	SEC_RESET_REASON_BOOTLOADER   = (SEC_RESET_REASON_PREFIX | 0xd), /* go to download mode */
	SEC_RESET_REASON_EMERGENCY = 0x0,

	SEC_RESET_SET_FORCE_UPLOAD = (SEC_RESET_SET_PREFIX | 0x40000),
	SEC_RESET_SET_DEBUG        = (SEC_RESET_SET_PREFIX | 0xd0000),
	SEC_RESET_SET_SWSEL        = (SEC_RESET_SET_PREFIX | 0xe0000),
	SEC_RESET_SET_SUD          = (SEC_RESET_SET_PREFIX | 0xf0000),
	SEC_RESET_CP_DBGMEM        = (SEC_RESET_SET_PREFIX | 0x50000), /* cpmem_on: CP RAM logging */
#if defined(CONFIG_SEC_ABC)
	SEC_RESET_USER_DRAM_TEST   = (SEC_RESET_SET_PREFIX | 0x60000), /* USER DRAM TEST */
#endif
};

static void sec_power_off(void)
{
	pr_emerg("%s: Always-On active -> rebooting system instead of powering off!\n", __func__);
	local_irq_disable();
	exynos_pmu_write(EXYNOS_PMU_INFORM2, SEC_POWER_RESET);
	flush_cache_all();
	mach_restart(REBOOT_SOFT, "sw reset");
	while (1)
		;
}

static void sec_reboot(enum reboot_mode reboot_mode, const char *cmd)
{
	local_irq_disable();

	pr_emerg("%s (%d, %s)\n", __func__, reboot_mode, cmd ? cmd : "(null)");

	/* LPM mode prevention */
	exynos_pmu_write(EXYNOS_PMU_INFORM2, SEC_POWER_RESET);

	if (cmd) {
		unsigned long value;
		if (!strcmp(cmd, "fota"))
			exynos_pmu_write(EXYNOS_PMU_INFORM3, SEC_RESET_REASON_FOTA);
		else if (!strcmp(cmd, "fota_bl"))
			exynos_pmu_write(EXYNOS_PMU_INFORM3, SEC_RESET_REASON_FOTA_BL);
		else if (!strcmp(cmd, "recovery"))
			exynos_pmu_write(EXYNOS_PMU_INFORM3, SEC_RESET_REASON_RECOVERY);
		else if (!strcmp(cmd, "download"))
			exynos_pmu_write(EXYNOS_PMU_INFORM3, SEC_RESET_REASON_DOWNLOAD);
		else if (!strcmp(cmd, "bootloader"))
			exynos_pmu_write(EXYNOS_PMU_INFORM3, SEC_RESET_REASON_BOOTLOADER);
		else if (!strcmp(cmd, "upload"))
			exynos_pmu_write(EXYNOS_PMU_INFORM3, SEC_RESET_REASON_UPLOAD);
		else if (!strcmp(cmd, "secure"))
			exynos_pmu_write(EXYNOS_PMU_INFORM3, SEC_RESET_REASON_SECURE);
		else if (!strcmp(cmd, "fwup"))
			exynos_pmu_write(EXYNOS_PMU_INFORM3, SEC_RESET_REASON_FWUP);
		else if (!strcmp(cmd, "em_mode_force_user"))
			exynos_pmu_write(EXYNOS_PMU_INFORM3, SEC_RESET_REASON_EM_FUSE);
#if defined(CONFIG_SEC_ABC)
		else if (!strcmp(cmd, "user_dram_test") && sec_abc_get_enabled())
			exynos_pmu_write(EXYNOS_PMU_INFORM3, SEC_RESET_USER_DRAM_TEST);
#endif
		else if (!strncmp(cmd, "emergency", 9))
			exynos_pmu_write(EXYNOS_PMU_INFORM3, SEC_RESET_REASON_EMERGENCY);
		else if (!strncmp(cmd, "debug", 5) && !kstrtoul(cmd + 5, 0, &value))
			exynos_pmu_write(EXYNOS_PMU_INFORM3, SEC_RESET_SET_DEBUG | value);
#if defined(CONFIG_SEC_DEBUG_SUPPORT_FORCE_UPLOAD)
		else if (!strncmp(cmd, "forceupload", 11) && !kstrtoul(cmd + 11, 0, &value))
			exynos_pmu_write(EXYNOS_PMU_INFORM3, SEC_RESET_SET_FORCE_UPLOAD | value);
#endif
		else if (!strncmp(cmd, "swsel", 5) && !kstrtoul(cmd + 5, 0, &value))
			exynos_pmu_write(EXYNOS_PMU_INFORM3, SEC_RESET_SET_SWSEL | value);
		else if (!strncmp(cmd, "sud", 3) && !kstrtoul(cmd + 3, 0, &value))
			exynos_pmu_write(EXYNOS_PMU_INFORM3, SEC_RESET_SET_SUD | value);
		else if (!strncmp(cmd, "cpmem_on", 8))
			exynos_pmu_write(EXYNOS_PMU_INFORM3, SEC_RESET_CP_DBGMEM | 0x1);
		else if (!strncmp(cmd, "cpmem_off", 9))
			exynos_pmu_write(EXYNOS_PMU_INFORM3, SEC_RESET_CP_DBGMEM | 0x2);
		else if (!strncmp(cmd, "mbsmem_on", 9))
			exynos_pmu_write(EXYNOS_PMU_INFORM3, SEC_RESET_CP_DBGMEM | 0x1);
		else if (!strncmp(cmd, "mbsmem_off", 10))
			exynos_pmu_write(EXYNOS_PMU_INFORM3, SEC_RESET_CP_DBGMEM | 0x2);
		else if (!strncmp(cmd, "panic", 5)) {
			extern int s9_boot_completed;
			if (!s9_boot_completed) {
				pr_emerg("sec_reboot: boot panic detected -> setting INFORM3 to RECOVERY\n");
				exynos_pmu_write(EXYNOS_PMU_INFORM3, SEC_RESET_REASON_RECOVERY);
			}
		} else
			exynos_pmu_write(EXYNOS_PMU_INFORM3, SEC_RESET_REASON_UNKNOWN);
	} else {
		exynos_pmu_write(EXYNOS_PMU_INFORM3, SEC_RESET_REASON_UNKNOWN);
	}

	flush_cache_all();
	mach_restart(REBOOT_SOFT, "sw reset");

	pr_emerg("%s: waiting for reboot\n", __func__);
	while (1)
		;
}

static int __init sec_reboot_init(void)
{
	mach_restart = arm_pm_restart;
	pm_power_off = sec_power_off;
	arm_pm_restart = sec_reboot;
	return 0;
}

subsys_initcall(sec_reboot_init);
