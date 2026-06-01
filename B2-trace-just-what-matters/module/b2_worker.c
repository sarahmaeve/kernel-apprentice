// SPDX-License-Identifier: GPL-2.0
/* b2_worker.c — lesson B2 (CHALLENGE): make a worker's phases show up in the trace.
 *
 * Writing to /proc/b2-go runs three phases. Right now they do their work in
 * silence — the function tracer can see that phase_parse/compute/emit ran, but not
 * WHAT happened inside. Your job: annotate each phase with trace_printk() so the
 * trace ring buffer narrates it. trace_printk() is printk's low-overhead cousin:
 * it writes into the trace buffer (read it at /sys/kernel/tracing/trace), not the
 * kernel log — cheap enough to leave in a hot path while you debug.
 *
 * The check looks for the lines "b2: parse", "b2: compute", and "b2: emit" in the
 * trace (see README for the exact spec). One phase is done as a worked example.
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/proc_fs.h>
#include <linux/uaccess.h>

#define PROC_NAME "b2-go"

static noinline void phase_parse(int n)
{
	/* worked example — this is all an annotation needs to be: */
	trace_printk("b2: parse %d bytes\n", n);
}

static noinline void phase_compute(int n)
{
	int sum = n * 3;   /* "work" */

	/* TODO(B2): annotate this phase too, so the trace shows a line containing
	 * "b2: compute" (see README). */
	(void)sum;
}

static noinline void phase_emit(int n)
{
	/* TODO(B2): annotate this phase so the trace shows a line containing
	 * "b2: emit". */
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
