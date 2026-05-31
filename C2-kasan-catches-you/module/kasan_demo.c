// SPDX-License-Identifier: GPL-2.0
/* kasan_demo.c — lesson C2: a deliberate slab out-of-bounds write.
 *
 * Built against the KASAN overlay kernel, so the compiler instruments this
 * module and KASAN checks every access. Load it and KASAN catches the bad write
 * the instant it happens — far more useful than the random crash you'd get later
 * on a normal kernel. Read the splat (the access stack, the "Allocated by task"
 * stack, the shadow map), then fix the bug below so KASAN goes silent.
 */
#include <linux/module.h>
#include <linux/slab.h>

#define LEN 64

static int __init kasan_demo_init(void)
{
	char *buf;
	int i;

	buf = kmalloc(LEN, GFP_KERNEL);
	if (!buf)
		return -ENOMEM;

	pr_info("kasan_demo: filling a %d-byte buffer\n", LEN);

	/*
	 * TODO(C2) — THE BUG: this loop runs i = 0 .. LEN (inclusive), so the last
	 * iteration writes buf[LEN] — one byte PAST the 64-byte allocation. KASAN
	 * reports it as "slab-out-of-bounds". The valid indices are buf[0 .. LEN-1].
	 *
	 * THE FIX: make the loop stop before LEN so every write stays in bounds.
	 */
	for (i = 0; i <= LEN; i++)
		buf[i] = (char)i;

	pr_info("kasan_demo: wrote the buffer; buf[%d] = %d\n", LEN - 1, buf[LEN - 1]);

	kfree(buf);
	pr_info("kasan_demo: done — no KASAN splat above means every access was in bounds\n");
	return 0;
}

static void __exit kasan_demo_exit(void)
{
	pr_info("kasan_demo: unloaded\n");
}

module_init(kasan_demo_init);
module_exit(kasan_demo_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Lesson C2: a slab out-of-bounds write that KASAN catches");
