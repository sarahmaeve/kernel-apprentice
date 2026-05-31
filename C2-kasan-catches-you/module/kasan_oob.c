// SPDX-License-Identifier: GPL-2.0
/* kasan_oob.c — lesson C2, part 1 of 3.
 *
 * Built against the KASAN kernel, so KASAN checks every access this module makes.
 * As shipped it has a planted bug: loading it produces a KASAN report whose access
 * stack points into this file. Read the report (the lesson page shows how) and fix
 * the module so it loads cleanly.
 */
#include <linux/module.h>
#include <linux/slab.h>

#define LEN 64

static int __init kasan_oob_init(void)
{
	char *buf;
	int i;

	buf = kmalloc(LEN, GFP_KERNEL);
	if (!buf)
		return -ENOMEM;

	pr_info("kasan_oob: writing a %d-byte buffer\n", LEN);

	for (i = 0; i <= LEN; i++)
		buf[i] = (char)i;

	kfree(buf);
	pr_info("kasan_oob: done\n");
	return 0;
}

static void __exit kasan_oob_exit(void) { }

module_init(kasan_oob_init);
module_exit(kasan_oob_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Lesson C2 part 1: a slab out-of-bounds write that KASAN catches");
