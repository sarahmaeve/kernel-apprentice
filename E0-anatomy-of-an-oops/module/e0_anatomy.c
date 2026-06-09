// SPDX-License-Identifier: GPL-2.0
/*
 * e0_anatomy.c — READY (run + observe). A crash SPECIMEN, not a bug to fix.
 *
 * Creates /proc/ka-anatomy. Write a command to it and the module produces that
 * failure on purpose, so you can read each report shape in dmesg:
 *
 *   echo warn > /proc/ka-anatomy    WARN()      loud complaint; execution continues
 *   echo bug  > /proc/ka-anatomy    BUG()       fatal assertion; the writer is killed
 *   echo oops > /proc/ka-anatomy    NULL deref  unexpected page fault; writer killed
 *
 * Nothing here is broken by accident and nothing needs fixing — the lesson is
 * reading what the kernel prints. See README.md.
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/proc_fs.h>
#include <linux/uaccess.h>
#include <linux/bug.h>
#include <linux/string.h>

#define PROC_NAME "ka-anatomy"

static ssize_t e0_write(struct file *file, const char __user *ubuf,
			size_t count, loff_t *ppos)
{
	char cmd[8] = "";
	size_t n = min_t(size_t, count, sizeof(cmd) - 1);

	if (copy_from_user(cmd, ubuf, n))
		return -EFAULT;
	cmd[n] = '\0';

	if (!strncmp(cmd, "warn", 4)) {
		WARN(1, "kernel-apprentice: E0 specimen WARN (a complaint, not a crash)");
		pr_info("kernel-apprentice: still running after the WARN\n");
		return count;
	}

	if (!strncmp(cmd, "bug", 3)) {
		pr_info("kernel-apprentice: E0 firing BUG() — fatal for this process\n");
		BUG();
		/* not reached */
	}

	if (!strncmp(cmd, "oops", 4)) {
		/* volatile: the compiler must not prove this NULL and fold the
		 * store into a trap — we want the genuine page-fault oops. */
		int * volatile nothing = NULL;

		pr_info("kernel-apprentice: E0 dereferencing NULL on purpose\n");
		*nothing = 0xdead;	/* RIP will point at this store */
		/* not reached */
	}

	return count;
}

static const struct proc_ops e0_proc_ops = {
	.proc_write = e0_write,
};

static int __init e0_init(void)
{
	if (!proc_create(PROC_NAME, 0222, NULL, &e0_proc_ops))
		return -ENOMEM;
	pr_info("kernel-apprentice: /proc/%s ready — write warn|bug|oops to it\n",
		PROC_NAME);
	return 0;
}

static void __exit e0_exit(void)
{
	remove_proc_entry(PROC_NAME, NULL);
}

module_init(e0_init);
module_exit(e0_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("kernel-apprentice");
MODULE_DESCRIPTION("READY: a crash specimen — produces a WARN, a BUG() or a NULL-deref oops on demand.");
