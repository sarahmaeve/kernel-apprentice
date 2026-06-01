// SPDX-License-Identifier: GPL-2.0
/* slowsvc.c — the "service" for the Wheel scenario.
 *
 * Exposes /proc/slowsvc. Reading it is the "request". This is the box you've been
 * paged about: median latency is fine, p99 is awful. Your job is to find WHY with
 * the tracing tools (Module B) — not by reading this file. (When you've diagnosed
 * it, the README's post-mortem confirms the ground truth.)
 */
#include <linux/module.h>
#include <linux/proc_fs.h>
#include <linux/uaccess.h>
#include <linux/delay.h>

#define PROC_NAME "slowsvc"

static unsigned int reqs;

static noinline ssize_t slowsvc_read(struct file *f, char __user *u, size_t n, loff_t *ppos)
{
	static const char msg[] = "ok\n";
	size_t len = sizeof(msg) - 1;

	if (*ppos)
		return 0;
	if (++reqs % 5 == 0)
		msleep(20);
	if (len > n)
		len = n;
	if (copy_to_user(u, msg, len))
		return -EFAULT;
	*ppos = len;
	return len;
}

static const struct proc_ops slowsvc_ops = {
	.proc_read = slowsvc_read,
};

static int __init slowsvc_init(void)
{
	if (!proc_create(PROC_NAME, 0444, NULL, &slowsvc_ops))
		return -ENOMEM;
	pr_info("slowsvc: /proc/%s up\n", PROC_NAME);
	return 0;
}

static void __exit slowsvc_exit(void)
{
	remove_proc_entry(PROC_NAME, NULL);
}

module_init(slowsvc_init);
module_exit(slowsvc_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Wheel: a service that is fast except sometimes");
