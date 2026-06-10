// SPDX-License-Identifier: GPL-2.0
/*
 * d2_race.c — CHALLENGE (read + fix).
 *
 * Two worker threads each process a batch of "events" (D2_ITERS apiece) and
 * count them in a shared total. Every event is counted exactly once, so the
 * total ought to be 2 * D2_ITERS — yet it comes up short, and on the debug
 * kernel KCSAN prints a report while the workers run. Read the report, work
 * out what its two stacks are telling you, and fix the code so the count is
 * exact and KCSAN stays silent. Then `make check`.
 *
 * No TODO markers — the report names the function; start there. Hints in the
 * README if you get stuck.
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/kthread.h>
#include <linux/completion.h>

#define D2_ITERS 200000

static long d2_total;

static DECLARE_COMPLETION(d2_start);
static DECLARE_COMPLETION(d2_done_a);
static DECLARE_COMPLETION(d2_done_b);

/* Count one processed event. */
static noinline void d2_count_event(void)
{
	d2_total++;
}

static int d2_worker(void *done)
{
	int i;

	wait_for_completion(&d2_start);	/* both workers start together */
	for (i = 0; i < D2_ITERS; i++)
		d2_count_event();
	complete(done);
	return 0;
}

static int __init d2_init(void)
{
	kthread_run(d2_worker, &d2_done_a, "d2-worker-a");
	kthread_run(d2_worker, &d2_done_b, "d2-worker-b");
	complete_all(&d2_start);
	wait_for_completion(&d2_done_a);
	wait_for_completion(&d2_done_b);
	pr_info("kernel-apprentice: d2_race counted %ld of %d events\n",
		d2_total, 2 * D2_ITERS);
	return 0;
}

static void __exit d2_exit(void) { }

module_init(d2_init);
module_exit(d2_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("kernel-apprentice");
MODULE_DESCRIPTION("CHALLENGE: two workers, one counter, a short total. KCSAN saw why. Read it, fix it.");
