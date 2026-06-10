// SPDX-License-Identifier: GPL-2.0
/*
 * d1_locks.c — CHALLENGE (read + fix).
 *
 * A tiny subsystem: a stats table and a cache, each guarded by its own mutex,
 * and two maintenance routines that need both. On the debug kernel (lockdep),
 * loading this module prints a WARNING. Your job: read the lockdep report,
 * work out what it is proving about these two routines, and fix the code so
 * the module loads with no warning. Then `make check`.
 *
 * There are no TODO markers — the report names everything it needs to.
 * Hints in the README if you get stuck.
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/mutex.h>

static DEFINE_MUTEX(d1_stats_lock);
static DEFINE_MUTEX(d1_cache_lock);

static int d1_stat_count;
static int d1_cache_count;

/* Recompute the stats table, folding in what the cache currently holds. */
static noinline void d1_refresh_stats(void)
{
	mutex_lock(&d1_stats_lock);
	mutex_lock(&d1_cache_lock);
	d1_stat_count = d1_cache_count + 1;
	mutex_unlock(&d1_cache_lock);
	mutex_unlock(&d1_stats_lock);
}

/* Drop the cache, recording the drop in the stats table. */
static noinline void d1_drop_caches(void)
{
	mutex_lock(&d1_cache_lock);
	mutex_lock(&d1_stats_lock);
	d1_cache_count = 0;
	d1_stat_count++;
	mutex_unlock(&d1_stats_lock);
	mutex_unlock(&d1_cache_lock);
}

static int __init d1_init(void)
{
	d1_refresh_stats();
	d1_drop_caches();
	pr_info("kernel-apprentice: d1_locks ran both maintenance routines (stats=%d)\n",
		d1_stat_count);
	return 0;
}

static void __exit d1_exit(void) { }

module_init(d1_init);
module_exit(d1_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("kernel-apprentice");
MODULE_DESCRIPTION("CHALLENGE: two routines, two locks — lockdep has an opinion. Read it, fix it.");
