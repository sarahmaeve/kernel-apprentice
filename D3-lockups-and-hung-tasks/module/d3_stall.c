// SPDX-License-Identifier: GPL-2.0
/*
 * d3_stall.c — READY (run + observe). A stall SPECIMEN, not a bug to fix.
 *
 * Creates /proc/d3-stall. Write a command to it and the module produces that
 * stall on purpose, so you can watch the kernel's own detectors fire:
 *
 *   echo spin > /proc/d3-stall   hog this CPU with preemption off for a few
 *                                seconds -> the soft-lockup watchdog reports it
 *   echo hang > /proc/d3-stall   park a kthread in D state -> khungtaskd (the
 *                                hung-task detector) reports it
 *
 * Nothing here is broken by accident and nothing needs fixing — the lesson is
 * reading what the detectors print. See README.md.
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/proc_fs.h>
#include <linux/uaccess.h>
#include <linux/kthread.h>
#include <linux/sched.h>
#include <linux/jiffies.h>
#include <linux/preempt.h>
#include <linux/string.h>

#define PROC_NAME "d3-stall"
#define SPIN_SECS 6

static struct task_struct *d3_hung_task;

/* Hog the current CPU: no schedule, no preemption, interrupts still on — the
 * shape of a kernel-side busy loop gone wrong. The watchdog runs from a timer
 * interrupt, so it can still observe us. */
static void d3_spin(void)
{
	unsigned long end = jiffies + SPIN_SECS * HZ;

	pr_info("kernel-apprentice: d3 hogging this CPU for %ds with preemption off\n",
		SPIN_SECS);
	preempt_disable();
	while (time_before(jiffies, end))
		cpu_relax();
	preempt_enable();
	pr_info("kernel-apprentice: d3 spin done — the CPU schedules again\n");
}

/* Park forever in uninterruptible sleep — the D state khungtaskd hunts for. */
static int d3_hung_fn(void *unused)
{
	pr_info("kernel-apprentice: d3-hung parking in D state — khungtaskd will notice\n");
	while (!kthread_should_stop()) {
		set_current_state(TASK_UNINTERRUPTIBLE);
		schedule();
	}
	return 0;
}

static ssize_t d3_write(struct file *file, const char __user *ubuf,
			size_t count, loff_t *ppos)
{
	char cmd[8] = "";
	size_t n = min_t(size_t, count, sizeof(cmd) - 1);

	if (copy_from_user(cmd, ubuf, n))
		return -EFAULT;
	cmd[n] = '\0';

	if (!strncmp(cmd, "spin", 4))
		d3_spin();

	if (!strncmp(cmd, "hang", 4) && !d3_hung_task)
		d3_hung_task = kthread_run(d3_hung_fn, NULL, "d3-hung");

	return count;
}

static const struct proc_ops d3_proc_ops = {
	.proc_write = d3_write,
};

static int __init d3_init(void)
{
	if (!proc_create(PROC_NAME, 0222, NULL, &d3_proc_ops))
		return -ENOMEM;
	pr_info("kernel-apprentice: /proc/%s ready — write spin|hang to it\n", PROC_NAME);
	return 0;
}

static void __exit d3_exit(void)
{
	remove_proc_entry(PROC_NAME, NULL);
	if (d3_hung_task)
		kthread_stop(d3_hung_task);
}

module_init(d3_init);
module_exit(d3_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("kernel-apprentice");
MODULE_DESCRIPTION("READY: stalls a CPU or a task on demand so the kernel's stall detectors have something to report.");
