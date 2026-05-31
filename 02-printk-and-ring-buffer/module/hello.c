// SPDX-License-Identifier: GPL-2.0
/*
 * hello.c — a real, complete loadable kernel module whose only job is to emit one
 * printk per log level, so you can see the kernel log ring buffer fill and watch
 * the console filter (console_loglevel) at work.
 *
 * Built out-of-tree against the pinned kernel by ../check.sh, then insmod'd in a
 * QEMU guest. Loading runs hello_init; unloading (rmmod) runs hello_exit.
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>

static int __init hello_init(void)
{
	pr_emerg ("kernel-apprentice: hello at EMERG (0)\n");
	pr_alert ("kernel-apprentice: hello at ALERT (1)\n");
	pr_crit  ("kernel-apprentice: hello at CRIT  (2)\n");
	pr_err   ("kernel-apprentice: hello at ERR   (3)\n");
	pr_warn  ("kernel-apprentice: hello at WARN  (4)\n");
	pr_notice("kernel-apprentice: hello at NOTICE(5)\n");
	pr_info  ("kernel-apprentice: hello at INFO  (6)\n");
	pr_debug ("kernel-apprentice: hello at DEBUG (7)\n"); /* silent unless dyndbg */
	return 0;
}

static void __exit hello_exit(void)
{
	pr_info("kernel-apprentice: goodbye\n");
}

module_init(hello_init);
module_exit(hello_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("kernel-apprentice");
MODULE_DESCRIPTION("Emit one printk per log level to demonstrate the ring buffer.");
