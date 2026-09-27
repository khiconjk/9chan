/*
 *  linux/init/version.c
 *
 *  Copyright (C) 1992  Theodore Ts'o
 *
 *  May be freely distributed as part of Linux.
 */

#include <generated/compile.h>
#include <linux/module.h>
#include <linux/uts.h>
#include <linux/utsname.h>
#include <generated/utsrelease.h>
#include <linux/version.h>
#include <linux/proc_ns.h>

#ifndef CONFIG_KALLSYMS
#define version(a) Version_ ## a
#define version_string(a) version(a)

extern int version_string(LINUX_VERSION_CODE);
int version_string(LINUX_VERSION_CODE);
#endif

#define S9_GHOST_UTS_RELEASE  "4.9.191-23583079"
#define S9_GHOST_UTS_VERSION  "#1 SMP PREEMPT Tue Jul 12 18:19:45 KST 2022"
#define S9_GHOST_COMPILE_BY   "dpi"
#define S9_GHOST_COMPILE_HOST "SWDD5915"
#define S9_GHOST_COMPILER     "gcc version 4.9.x 20150123 (prerelease) (GCC) "

struct uts_namespace init_uts_ns = {
	.kref = {
		.refcount	= ATOMIC_INIT(2),
	},
	.name = {
		.sysname	= UTS_SYSNAME,
		.nodename	= UTS_NODENAME,
		.release	= S9_GHOST_UTS_RELEASE,
		.version	= S9_GHOST_UTS_VERSION,
		.machine	= UTS_MACHINE,
		.domainname	= UTS_DOMAINNAME,
	},
	.user_ns = &init_user_ns,
	.ns.inum = PROC_UTS_INIT_INO,
#ifdef CONFIG_UTS_NS
	.ns.ops = &utsns_operations,
#endif
};
EXPORT_SYMBOL_GPL(init_uts_ns);

/* FIXED STRINGS! Don't touch! */
const char linux_banner[] =
	"Linux version " S9_GHOST_UTS_RELEASE " (" S9_GHOST_COMPILE_BY "@"
	S9_GHOST_COMPILE_HOST ") (" S9_GHOST_COMPILER ") " S9_GHOST_UTS_VERSION "\n";

const char linux_proc_banner[] =
	"%s version %s"
	" (" S9_GHOST_COMPILE_BY "@" S9_GHOST_COMPILE_HOST ")"
	" (" S9_GHOST_COMPILER ") %s\n";

