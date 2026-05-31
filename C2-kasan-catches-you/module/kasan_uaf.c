// SPDX-License-Identifier: GPL-2.0
/* kasan_uaf.c — lesson C2, part 2 of 3.
 *
 * Built against the KASAN kernel, so KASAN checks every access this module makes.
 * As shipped it has a planted bug: loading it produces a KASAN report that carries
 * an extra "Freed by task" stack. Read all three stacks, find the bad access in
 * this file, and fix the module so it loads cleanly.
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

	first = c->host[0];
	pr_info("kasan_uaf: closed conn (host began '%c')\n", first);

	return 0;
}

static void __exit kasan_uaf_exit(void) { }

module_init(kasan_uaf_init);
module_exit(kasan_uaf_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Lesson C2 part 2: a use-after-free that KASAN catches");
