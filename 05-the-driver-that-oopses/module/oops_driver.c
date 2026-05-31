// SPDX-License-Identifier: GPL-2.0
/*
 * oops_driver.c — CHALLENGE (read + fix).
 *
 * This module creates /proc/ka-oops. Writing to it crashes the kernel — a NULL
 * pointer dereference oops. Your job: trigger it, READ the oops in dmesg, trace the
 * RIP / call trace back to the buggy line in this file, find what's NULL, and fix it
 * so the write succeeds (no oops). Then `make check`.
 *
 * There are no TODO markers — this is a "read the trace, find the bug" lesson.
 * Hints in the README if you get stuck.
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/proc_fs.h>
#include <linux/uaccess.h>
#include <linux/slab.h>
#include <linux/string.h>

#define PROC_NAME "ka-oops"
#define BUFSZ 64

struct ka_state {
	char  *buf;
	size_t len;
};

static struct ka_state *state;

static ssize_t ka_write(struct file *file, const char __user *ubuf,
			size_t count, loff_t *ppos)
{
	char tmp[BUFSZ];
	size_t n = min_t(size_t, count, BUFSZ - 1);

	if (copy_from_user(tmp, ubuf, n))
		return -EFAULT;
	tmp[n] = '\0';

	/* stash the message in our state buffer */
	memcpy(state->buf, tmp, n + 1);
	state->len = n;

	pr_info("kernel-apprentice: ka-oops stored %zu bytes\n", n);
	return count;
}

static const struct proc_ops ka_proc_ops = {
	.proc_write = ka_write,
};

static int __init ka_init(void)
{
	state = kzalloc(sizeof(*state), GFP_KERNEL);
	if (!state)
		return -ENOMEM;

	if (!proc_create(PROC_NAME, 0222, NULL, &ka_proc_ops)) {
		kfree(state);
		return -ENOMEM;
	}
	pr_info("kernel-apprentice: /proc/%s ready (write to it)\n", PROC_NAME);
	return 0;
}

static void __exit ka_exit(void)
{
	remove_proc_entry(PROC_NAME, NULL);
	kfree(state->buf);
	kfree(state);
}

module_init(ka_init);
module_exit(ka_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("kernel-apprentice");
MODULE_DESCRIPTION("CHALLENGE: a driver that oopses on write — read the trace, find and fix the NULL deref.");
