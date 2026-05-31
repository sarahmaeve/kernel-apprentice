// SPDX-License-Identifier: GPL-2.0
/* kasan_uaf.c — lesson C2, part 2 of 3: a use-after-free.
 *
 * The meatier bug. On a normal kernel this is the classic "spooky action at a
 * distance" — the object is reused under you and you crash much later, somewhere
 * unrelated. KASAN catches the access the instant it happens and adds a THIRD
 * stack the out-of-bounds report didn't have: "Freed by task", pointing at the
 * kfree. Read all three (bad access / Allocated by / Freed by), then fix the
 * lifetime bug.
 *
 * Note the field we touch is host[] — deliberately NOT the first bytes of the
 * object. When SLUB frees a small object it stows its freelist pointer in the
 * first 8 bytes and KASAN leaves *that slot* accessible, so touching offset 0 of
 * a freed object can read back the (poisoned-shadow-exempt) freelist pointer with
 * no report. host[] sits past it, in memory KASAN genuinely guards.
 */
#include <linux/module.h>
#include <linux/slab.h>
#include <linux/string.h>

struct conn {
	int  id;
	char host[32];
};

static int __init kasan_uaf_init(void)
{
	struct conn *c;
	char first;

	c = kmalloc(sizeof(*c), GFP_KERNEL);
	if (!c)
		return -ENOMEM;
	c->id = 42;
	strscpy(c->host, "db.internal", sizeof(c->host));

	pr_info("kasan_uaf: opened conn %d to %s\n", c->id, c->host);

	kfree(c);

	/*
	 * TODO(C2 part 2) — THE BUG: c was just kfree'd above, but this reads
	 * c->host[0] AFTER the free. KASAN reports slab-use-after-free (a Read), and
	 * its "Freed by task" stack points at the kfree above.
	 *
	 * THE FIX: it's a lifetime bug, not a typo — read the conn BEFORE you free it.
	 * Move this read (and the log) above the kfree(c).
	 */
	first = c->host[0];
	pr_info("kasan_uaf: closed conn (host began '%c')\n", first);

	return 0;
}

static void __exit kasan_uaf_exit(void) { }

module_init(kasan_uaf_init);
module_exit(kasan_uaf_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Lesson C2 part 2: a use-after-free that KASAN catches");
