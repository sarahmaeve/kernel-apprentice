// SPDX-License-Identifier: GPL-2.0
/*
 * h2_wedge.c — READY (run + observe). Wedges a kernel thread on purpose.
 *
 * Loading this module starts a kthread named "h2-wedged" that parks itself in
 * TASK_UNINTERRUPTIBLE — the dreaded D state: not runnable, not killable,
 * deaf to signals. It is the controlled stand-in for "the process that won't
 * die"; SysRq (t/w) and /proc/<pid>/stack show exactly where it sleeps.
 *
 * Nothing here is broken by accident and nothing needs fixing — the lesson is
 * pulling state out of a wedged box. See README.md.
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/kthread.h>
#include <linux/sched.h>

static struct task_struct *h2_task;

static int h2_wedge_fn(void *unused)
{
	pr_info("kernel-apprentice: h2-wedged parking in D state (uninterruptible)\n");
	while (!kthread_should_stop()) {
		set_current_state(TASK_UNINTERRUPTIBLE);
		schedule();	/* parked here — the frame w and /proc/<pid>/stack show */
	}
	return 0;
}

static int __init h2_init(void)
{
	h2_task = kthread_run(h2_wedge_fn, NULL, "h2-wedged");
	if (IS_ERR(h2_task))
		return PTR_ERR(h2_task);
	pr_info("kernel-apprentice: h2_wedge loaded — somewhere a thread is now stuck in D\n");
	return 0;
}

static void __exit h2_exit(void)
{
	kthread_stop(h2_task);	/* wakes it; the loop sees should_stop and exits */
}

module_init(h2_init);
module_exit(h2_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("kernel-apprentice");
MODULE_DESCRIPTION("READY: parks a kthread in D state so SysRq has something wedged to show.");
