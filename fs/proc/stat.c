#include <linux/cpumask.h>
#include <linux/fs.h>
#include <linux/init.h>
#include <linux/interrupt.h>
#include <linux/kernel_stat.h>
#include <linux/proc_fs.h>
#include <linux/sched.h>
#include <linux/seq_file.h>
#include <linux/slab.h>
#include <linux/time.h>
#include <linux/irqnr.h>
#include <linux/cputime.h>
#include <linux/tick.h>
#include <linux/ghost_uptime.h>

#ifdef CONFIG_LOD_SEC
#include <linux/linux_on_dex.h>
#endif

#ifndef arch_irq_stat_cpu
#define arch_irq_stat_cpu(cpu) 0
#endif
#ifndef arch_irq_stat
#define arch_irq_stat() 0
#endif

#ifdef arch_idle_time

static u64 get_idle_time(int cpu)
{
	u64 idle;

	idle = kcpustat_cpu(cpu).cpustat[CPUTIME_IDLE];
	if (cpu_online(cpu) && !nr_iowait_cpu(cpu))
		idle += cputime_to_nsecs(arch_idle_time(cpu));
	return idle;
}

static u64 get_iowait_time(int cpu)
{
	u64 iowait;

	iowait = kcpustat_cpu(cpu).cpustat[CPUTIME_IOWAIT];
	if (cpu_online(cpu) && nr_iowait_cpu(cpu))
		iowait += cputime_to_nsecs(arch_idle_time(cpu));
	return iowait;
}

#else

static u64 get_idle_time(int cpu)
{
	u64 idle, idle_usecs = -1ULL;

	if (cpu_online(cpu))
		idle_usecs = get_cpu_idle_time_us(cpu, NULL);

	if (idle_usecs == -1ULL)
		/* !NO_HZ or cpu offline so we can rely on cpustat.idle */
		idle = kcpustat_cpu(cpu).cpustat[CPUTIME_IDLE];
	else
		idle = idle_usecs * NSEC_PER_USEC;

	return idle;
}

static u64 get_iowait_time(int cpu)
{
	u64 iowait, iowait_usecs = -1ULL;

	if (cpu_online(cpu))
		iowait_usecs = get_cpu_iowait_time_us(cpu, NULL);

	if (iowait_usecs == -1ULL)
		/* !NO_HZ or cpu offline so we can rely on cpustat.iowait */
		iowait = kcpustat_cpu(cpu).cpustat[CPUTIME_IOWAIT];
	else
		iowait = iowait_usecs * NSEC_PER_USEC;

	return iowait;
}

#endif

static int show_stat(struct seq_file *p, void *v)
{
	int i, j;
	u64 user, nice, system, idle, iowait, irq, softirq, steal;
	u64 guest, guest_nice;
	u64 sum = 0;
	u64 sum_softirq = 0;
	unsigned int per_softirq_sums[NR_SOFTIRQS] = {0};
	struct timespec64 boottime;
	u64 g_user = 0, g_nice = 0, g_sys = 0, g_idle = 0, g_iowait = 0;
	u64 g_irq = 0, g_softirq = 0;
	u64 ghost_ctxt = 0, ghost_procs = 0;

	if (s9_ghost_uptime_offset_sec > 0) {
		u64 ghost_base_ns = s9_ghost_uptime_offset_sec * NSEC_PER_SEC;
		/* DETECT-3: Realistic distribution across ALL tick categories */
		g_idle    = (ghost_base_ns / 1000ULL) * 870ULL;  /* 87.0% */
		g_user    = (ghost_base_ns / 1000ULL) * 58ULL;   /* 5.8% */
		g_nice    = (ghost_base_ns / 1000ULL) * 15ULL;   /* 1.5% */
		g_sys     = (ghost_base_ns / 1000ULL) * 40ULL;   /* 4.0% */
		g_iowait  = (ghost_base_ns / 1000ULL) * 10ULL;   /* 1.0% */
		g_irq     = (ghost_base_ns / 1000ULL) * 3ULL;    /* 0.3% */
		g_softirq = (ghost_base_ns / 1000ULL) * 4ULL;    /* 0.4% */
		/* Total: 100.0% */

		/* DETECT-4: Ghost context switches (~500/sec) and forks (~0.5/sec) */
		ghost_ctxt = s9_ghost_uptime_offset_sec * 500ULL;
		ghost_procs = s9_ghost_uptime_offset_sec / 2ULL;
	}

	user = nice = system = idle = iowait =
		irq = softirq = steal = 0;
	guest = guest_nice = 0;
	getboottime64(&boottime);

	for_each_possible_cpu(i) {
		/*
		 * DETECT-1: Per-core variance for big.LITTLE (Exynos 9810).
		 * Cores 0-3 (Mongoose M3 big): 1.15x user/sys (run more)
		 * Cores 4-7 (Cortex-A55 LITTLE): 0.85x user/sys (idle more)
		 * Jitter: ±(cpu_index * 3)% for natural variation.
		 */
		u64 scale_user, scale_nice, scale_sys, scale_idle;
		u64 scale_iowait, scale_irq, scale_softirq;
		u64 jitter = (u64)(i * 3);

		if (i < 4) {
			/* Big cores: more active, less idle */
			scale_user    = g_user + (g_user * (15 + jitter)) / 1000;
			scale_nice    = g_nice + (g_nice * (10 + jitter)) / 1000;
			scale_sys     = g_sys  + (g_sys  * (15 + jitter)) / 1000;
			scale_idle    = g_idle - (g_idle * (20 + jitter)) / 1000;
			scale_iowait  = g_iowait + (g_iowait * jitter) / 1000;
			scale_irq     = g_irq  + (g_irq  * (20 + jitter)) / 1000;
			scale_softirq = g_softirq + (g_softirq * (15 + jitter)) / 1000;
		} else {
			/* LITTLE cores: less active, more idle */
			scale_user    = g_user - (g_user * (15 + jitter)) / 1000;
			scale_nice    = g_nice - (g_nice * (10 + jitter)) / 1000;
			scale_sys     = g_sys  - (g_sys  * (15 + jitter)) / 1000;
			scale_idle    = g_idle + (g_idle * (10 + jitter)) / 1000;
			scale_iowait  = g_iowait - (g_iowait * jitter) / 1000;
			scale_irq     = g_irq  - (g_irq  * (10 + jitter)) / 1000;
			scale_softirq = g_softirq - (g_softirq * (10 + jitter)) / 1000;
		}

		user += kcpustat_cpu(i).cpustat[CPUTIME_USER] + scale_user;
		nice += kcpustat_cpu(i).cpustat[CPUTIME_NICE] + scale_nice;
		system += kcpustat_cpu(i).cpustat[CPUTIME_SYSTEM] + scale_sys;
		idle += get_idle_time(i) + scale_idle;
		iowait += get_iowait_time(i) + scale_iowait;
		irq += kcpustat_cpu(i).cpustat[CPUTIME_IRQ] + scale_irq;
		softirq += kcpustat_cpu(i).cpustat[CPUTIME_SOFTIRQ] + scale_softirq;
		steal += kcpustat_cpu(i).cpustat[CPUTIME_STEAL];
		guest += kcpustat_cpu(i).cpustat[CPUTIME_GUEST];
		guest_nice += kcpustat_cpu(i).cpustat[CPUTIME_GUEST_NICE];
		sum += kstat_cpu_irqs_sum(i);
		sum += arch_irq_stat_cpu(i);

		for (j = 0; j < NR_SOFTIRQS; j++) {
			unsigned int softirq_stat = kstat_softirqs_cpu(j, i);

			per_softirq_sums[j] += softirq_stat;
			sum_softirq += softirq_stat;
		}
	}
	sum += arch_irq_stat();

	seq_put_decimal_ull(p, "cpu  ", nsec_to_clock_t(user));
	seq_put_decimal_ull(p, " ", nsec_to_clock_t(nice));
	seq_put_decimal_ull(p, " ", nsec_to_clock_t(system));
	seq_put_decimal_ull(p, " ", nsec_to_clock_t(idle));
	seq_put_decimal_ull(p, " ", nsec_to_clock_t(iowait));
	seq_put_decimal_ull(p, " ", nsec_to_clock_t(irq));
	seq_put_decimal_ull(p, " ", nsec_to_clock_t(softirq));
	seq_put_decimal_ull(p, " ", nsec_to_clock_t(steal));
	seq_put_decimal_ull(p, " ", nsec_to_clock_t(guest));
	seq_put_decimal_ull(p, " ", nsec_to_clock_t(guest_nice));
	seq_putc(p, '\n');

	for_each_online_cpu(i) {
		u64 sc_user, sc_nice, sc_sys, sc_idle;
		u64 sc_iowait, sc_irq, sc_softirq;
		u64 jitter = (u64)(i * 3);

		if (s9_ghost_uptime_offset_sec > 0) {
			if (i < 4) {
				sc_user    = g_user + (g_user * (15 + jitter)) / 1000;
				sc_nice    = g_nice + (g_nice * (10 + jitter)) / 1000;
				sc_sys     = g_sys  + (g_sys  * (15 + jitter)) / 1000;
				sc_idle    = g_idle - (g_idle * (20 + jitter)) / 1000;
				sc_iowait  = g_iowait + (g_iowait * jitter) / 1000;
				sc_irq     = g_irq  + (g_irq  * (20 + jitter)) / 1000;
				sc_softirq = g_softirq + (g_softirq * (15 + jitter)) / 1000;
			} else {
				sc_user    = g_user - (g_user * (15 + jitter)) / 1000;
				sc_nice    = g_nice - (g_nice * (10 + jitter)) / 1000;
				sc_sys     = g_sys  - (g_sys  * (15 + jitter)) / 1000;
				sc_idle    = g_idle + (g_idle * (10 + jitter)) / 1000;
				sc_iowait  = g_iowait - (g_iowait * jitter) / 1000;
				sc_irq     = g_irq  - (g_irq  * (10 + jitter)) / 1000;
				sc_softirq = g_softirq - (g_softirq * (10 + jitter)) / 1000;
			}
		} else {
			sc_user = sc_nice = sc_sys = sc_idle = 0;
			sc_iowait = sc_irq = sc_softirq = 0;
		}

		/* Copy values here to work around gcc-2.95.3, gcc-2.96 */
		user = kcpustat_cpu(i).cpustat[CPUTIME_USER] + sc_user;
		nice = kcpustat_cpu(i).cpustat[CPUTIME_NICE] + sc_nice;
		system = kcpustat_cpu(i).cpustat[CPUTIME_SYSTEM] + sc_sys;
		idle = get_idle_time(i) + sc_idle;
		iowait = get_iowait_time(i) + sc_iowait;
		irq = kcpustat_cpu(i).cpustat[CPUTIME_IRQ] + sc_irq;
		softirq = kcpustat_cpu(i).cpustat[CPUTIME_SOFTIRQ] + sc_softirq;
		steal = kcpustat_cpu(i).cpustat[CPUTIME_STEAL];
		guest = kcpustat_cpu(i).cpustat[CPUTIME_GUEST];
		guest_nice = kcpustat_cpu(i).cpustat[CPUTIME_GUEST_NICE];
		seq_printf(p, "cpu%d", i);
		seq_put_decimal_ull(p, " ", nsec_to_clock_t(user));
		seq_put_decimal_ull(p, " ", nsec_to_clock_t(nice));
		seq_put_decimal_ull(p, " ", nsec_to_clock_t(system));
		seq_put_decimal_ull(p, " ", nsec_to_clock_t(idle));
		seq_put_decimal_ull(p, " ", nsec_to_clock_t(iowait));
		seq_put_decimal_ull(p, " ", nsec_to_clock_t(irq));
		seq_put_decimal_ull(p, " ", nsec_to_clock_t(softirq));
		seq_put_decimal_ull(p, " ", nsec_to_clock_t(steal));
		seq_put_decimal_ull(p, " ", nsec_to_clock_t(guest));
		seq_put_decimal_ull(p, " ", nsec_to_clock_t(guest_nice));
		seq_putc(p, '\n');
	}
#ifdef CONFIG_LOD_SEC
	seq_put_decimal_ull(p, "intr ", current_is_LOD() ? 0ULL : (unsigned long long)sum);
#else
	seq_put_decimal_ull(p, "intr ", (unsigned long long)sum);
#endif

	/* sum again ? it could be updated? */
	for_each_irq_nr(j)
#ifdef CONFIG_LOD_SEC
		seq_put_decimal_ull(p, " ", current_is_LOD() ? 0ULL : kstat_irqs_usr(j));
#else
		seq_put_decimal_ull(p, " ", kstat_irqs_usr(j));
#endif

	seq_printf(p,
		"\nctxt %llu\n"
		"btime %llu\n"
		"processes %lu\n"
		"procs_running %lu\n"
		"procs_blocked %lu\n",
#ifdef CONFIG_LOD_SEC
		current_is_LOD() ? 0ULL : (nr_context_switches() + ghost_ctxt),
#else
		nr_context_switches() + ghost_ctxt,
#endif
		(unsigned long long)boottime.tv_sec,
		total_forks + (unsigned long)ghost_procs,
		nr_running(),
		nr_iowait());

	seq_put_decimal_ull(p, "softirq ", (unsigned long long)sum_softirq);

	for (i = 0; i < NR_SOFTIRQS; i++)
		seq_put_decimal_ull(p, " ", per_softirq_sums[i]);
	seq_putc(p, '\n');

	return 0;
}

static int stat_open(struct inode *inode, struct file *file)
{
	size_t size = 1024 + 128 * num_online_cpus();

	/* minimum size to display an interrupt count : 2 bytes */
	size += 2 * nr_irqs;
	return single_open_size(file, show_stat, NULL, size);
}

static const struct file_operations proc_stat_operations = {
	.open		= stat_open,
	.read		= seq_read,
	.llseek		= seq_lseek,
	.release	= single_release,
};

static int __init proc_stat_init(void)
{
	proc_create("stat", 0, NULL, &proc_stat_operations);
	return 0;
}
fs_initcall(proc_stat_init);
