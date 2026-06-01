// SPDX-License-Identifier: GPL-2.0
/* b2_worker.c — lesson B2 (CHALLENGE): make a silent worker show up in the trace.
 *
 * Writing to /proc/b2-go runs three phases, but they run in silence. Make each one
 * announce itself in the trace ring buffer (/sys/kernel/tracing/trace) so a line
 * carrying its marker — "b2: parse", "b2: compute", "b2: emit" — appears. The lesson
 * page covers the how; the check greps the trace for each marker.
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/proc_fs.h>
#include <linux/uaccess.h>

#define PROC_NAME "b2-go"

static noinline void phase_parse(int n)
{
	/* TODO(B2): make this phase show a line containing "b2: parse" in the trace. */
	(void)n;
}

static noinline void phase_compute(int n)
{
	int sum = n * 3;   /* "work" */

	/* TODO(B2): make this phase show a line containing "b2: compute" in the trace. */
	(void)sum;
}

static noinline void phase_emit(int n)
{
	/* TODO(B2): make this phase show a line containing "b2: emit" in the trace. */
	(void)n;
}

static ssize_t b2_write(struct file *f, const char __user *u, size_t n, loff_t *ppos)
{
	phase_parse(n);
	phase_compute(n);
	phase_emit(n);
	return n;
}

static const struct proc_ops b2_ops = {
	.proc_write = b2_write,
};

static int __init b2_init(void)
{
	if (!proc_create(PROC_NAME, 0222, NULL, &b2_ops))
		return -ENOMEM;
	pr_info("b2_worker: write to /proc/%s to run the phases\n", PROC_NAME);
	return 0;
}

static void __exit b2_exit(void)
{
	remove_proc_entry(PROC_NAME, NULL);
}

module_init(b2_init);
module_exit(b2_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Lesson B2: annotate a worker's phases with trace_printk");
