// SPDX-License-Identifier: GPL-2.0
/* kasan_df.c — lesson C2, part 3 of 3.
 *
 * Built against the KASAN kernel, so KASAN checks every access this module makes.
 * As shipped it has a planted bug: loading it produces a KASAN report in a
 * different category from the other two. Read the report, find the cause in this
 * file, and fix the module so it loads cleanly.
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
	kfree(p);

	pr_info("kasan_df: done\n");
	return 0;
}

static void __exit kasan_df_exit(void) { }

module_init(kasan_df_init);
module_exit(kasan_df_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Lesson C2 part 3: a double-free that KASAN catches");
