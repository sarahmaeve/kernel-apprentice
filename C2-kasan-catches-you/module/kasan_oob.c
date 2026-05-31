// SPDX-License-Identifier: GPL-2.0
/* kasan_oob.c — lesson C2, part 1 of 3: a slab out-of-bounds write.
 *
 * The gentlest KASAN bug: one byte past a kmalloc. Read the splat's access stack
 * (where the bad write is), its "Allocated by task" stack (which object you ran
 * past), and the shadow map (00 = in-bounds, fc = redzone). Then fix the off-by-one.
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

	/*
	 * TODO(C2 part 1) — THE BUG: i runs 0 .. LEN *inclusive*, so the last write
	 * lands on buf[LEN] — one byte PAST the 64-byte allocation. KASAN reports
	 * slab-out-of-bounds. Valid indices are buf[0 .. LEN-1].
	 *
	 * THE FIX: stop before LEN (i < LEN) so the loop stays in bounds.
	 */
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
