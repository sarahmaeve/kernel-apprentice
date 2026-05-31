// SPDX-License-Identifier: GPL-2.0
/*
 * counter.c — CHALLENGE skeleton.
 *
 * Goal: count how many times getpid is called and expose the count at
 *       /proc/kernel-apprentice-count.
 *
 * The kprobe registration and the /proc plumbing are DONE for you. You implement
 * the two functions marked TODO (see this lesson's README), then `make check`:
 *   1) ka_pre_handler() — runs on every getpid call; make it bump the counter.
 *   2) ka_show()        — make it print exactly  "getpid calls: <N>\n".
 *
 * Left as-is, this compiles and loads but the counter never moves and /proc is
 * empty — so the check is red until you fill it in.
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/kprobes.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/atomic.h>

#define PROC_NAME  "kernel-apprentice-count"
#define PROBE_SYM  "__x64_sys_getpid"

/* __maybe_unused lets the skeleton compile under the kernel's -Werror before you
 * wire up the TODOs; once you use ka_count it's a harmless no-op. */
static atomic_t ka_count __maybe_unused = ATOMIC_INIT(0);

/* Runs just before every call to PROBE_SYM in the live kernel. */
static int ka_pre_handler(struct kprobe *p, struct pt_regs *regs)
{
	/* TODO 1: bump ka_count by one.  (hint: atomic_inc) */
	return 0;
}

static struct kprobe ka_kp = {
	.symbol_name = PROBE_SYM,
	.pre_handler = ka_pre_handler,
};

/* Produces the contents of /proc/kernel-apprentice-count on each read. */
static int ka_show(struct seq_file *m, void *v)
{
	/* TODO 2: print exactly  "getpid calls: N\n"  where N = atomic_read(&ka_count). */
	return 0;
}

static int ka_open(struct inode *inode, struct file *file)
{
	return single_open(file, ka_show, NULL);
}

static const struct proc_ops ka_proc_ops = {
	.proc_open    = ka_open,
	.proc_read    = seq_read,
	.proc_lseek   = seq_lseek,
	.proc_release = single_release,
};

static struct proc_dir_entry *ka_entry;

static int __init ka_init(void)
{
	int ret = register_kprobe(&ka_kp);

	if (ret) {
		pr_err("kernel-apprentice: register_kprobe(%s) failed: %d\n", PROBE_SYM, ret);
		return ret;
	}
	ka_entry = proc_create(PROC_NAME, 0444, NULL, &ka_proc_ops);
	if (!ka_entry) {
		unregister_kprobe(&ka_kp);
		return -ENOMEM;
	}
	pr_info("kernel-apprentice: counting %s -> /proc/%s\n", PROBE_SYM, PROC_NAME);
	return 0;
}

static void __exit ka_exit(void)
{
	proc_remove(ka_entry);
	unregister_kprobe(&ka_kp);
	pr_info("kernel-apprentice: counter removed\n");
}

module_init(ka_init);
module_exit(ka_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("kernel-apprentice");
MODULE_DESCRIPTION("CHALLENGE: count getpid calls via a kprobe and expose them at /proc.");
