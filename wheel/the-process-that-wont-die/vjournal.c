// SPDX-License-Identifier: GPL-2.0
/*
 * vjournal.c — Wheel of Misfortune: "The process that won't die" (the injected
 * fault). A "vendor journal driver": userspace writes records to /proc/vjournal
 * and an internal compaction thread maintains the journal.
 *
 * DO NOT read this file while playing the scenario — drive the box first
 * (README.md). The post-mortem walks this code.
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/proc_fs.h>
#include <linux/mutex.h>
#include <linux/kthread.h>
#include <linux/sched.h>
#include <linux/uaccess.h>

#define PROC_NAME "vjournal"

static DEFINE_MUTEX(vjournal_lock);
static struct task_struct *vjournal_thread;
static long vjournal_records;

/* The compaction pass: takes the journal lock, then waits for "device I/O"
 * that never completes — wedged in D, holding the lock. */
static int vjournal_compact_fn(void *unused)
{
	mutex_lock(&vjournal_lock);
	pr_info("vjournal: compaction started\n");
	while (!kthread_should_stop()) {
		set_current_state(TASK_UNINTERRUPTIBLE);
		schedule();
	}
	mutex_unlock(&vjournal_lock);
	return 0;
}

static ssize_t vjournal_write(struct file *f, const char __user *ubuf,
			      size_t count, loff_t *ppos)
{
	mutex_lock(&vjournal_lock);	/* waits for compaction — in D state */
	vjournal_records++;
	mutex_unlock(&vjournal_lock);
	return count;
}

static const struct proc_ops vjournal_proc_ops = {
	.proc_write = vjournal_write,
};

static int __init vjournal_init(void)
{
	if (!proc_create(PROC_NAME, 0222, NULL, &vjournal_proc_ops))
		return -ENOMEM;
	vjournal_thread = kthread_run(vjournal_compact_fn, NULL, "vjournal-compact");
	if (IS_ERR(vjournal_thread)) {
		remove_proc_entry(PROC_NAME, NULL);
		return PTR_ERR(vjournal_thread);
	}
	pr_info("vjournal: ready (/proc/%s)\n", PROC_NAME);
	return 0;
}

static void __exit vjournal_exit(void)
{
	kthread_stop(vjournal_thread);
	remove_proc_entry(PROC_NAME, NULL);
}

module_init(vjournal_init);
module_exit(vjournal_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("kernel-apprentice");
MODULE_DESCRIPTION("Wheel fault injection: a vendor journal driver whose compaction thread wedges holding the lock.");
