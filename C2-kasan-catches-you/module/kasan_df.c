// SPDX-License-Identifier: GPL-2.0
/* kasan_df.c — lesson C2, part 3 of 3: a double-free.
 *
 * A different report category: "double-free or invalid-free". The realistic
 * shape is two cleanup paths that both free the same object (an error path that
 * frees, then the normal path frees again). KASAN catches the second free and
 * refuses it. Fix: free exactly once.
 */
#include <linux/module.h>
#include <linux/slab.h>

static int __init kasan_df_init(void)
{
	char *p;

	p = kmalloc(64, GFP_KERNEL);
	if (!p)
		return -ENOMEM;

	pr_info("kasan_df: allocated, now releasing\n");
	kfree(p);

	/*
	 * TODO(C2 part 3) — THE BUG: p was already freed just above; this frees it a
	 * second time (imagine a duplicated error/cleanup path). KASAN reports
	 * double-free or invalid-free.
	 *
	 * THE FIX: free p exactly once — remove this second kfree. (Defensively, code
	 * often also sets p = NULL after freeing, since kfree(NULL) is a safe no-op.)
	 */
	kfree(p);

	pr_info("kasan_df: done\n");
	return 0;
}

static void __exit kasan_df_exit(void) { }

module_init(kasan_df_init);
module_exit(kasan_df_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Lesson C2 part 3: a double-free that KASAN catches");
