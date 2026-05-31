// SPDX-License-Identifier: GPL-2.0
/*
 * ka_chardev.c — CHALLENGE skeleton.
 *
 * A misc character device, /dev/ka-chardev, backed by a small in-kernel buffer.
 * Implement its three operations so the userspace test (test.c) passes:
 *   1) ka_write — store the bytes written into ka_buf; remember the length.
 *   2) ka_read  — return the stored bytes to userspace (EOF on a second read).
 *   3) ka_ioctl — handle KA_GET_LEN: return the stored length.
 *
 * Registration (misc_register) and the /dev node are done for you. The stubs below
 * compile and load, but the device does nothing useful — so `make check` is red
 * until you fill them in. See the README for hints.
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/miscdevice.h>
#include <linux/fs.h>
#include <linux/uaccess.h>

#define DEV_NAME "ka-chardev"
#define BUFSZ    256

/* ioctl: KA_GET_LEN returns the number of bytes currently stored (an int). */
#define KA_IOC_MAGIC 'K'
#define KA_GET_LEN   _IOR(KA_IOC_MAGIC, 1, int)

static char   ka_buf[BUFSZ] __maybe_unused;
static size_t ka_len        __maybe_unused;

static ssize_t ka_read(struct file *f, char __user *ubuf, size_t count, loff_t *ppos)
{
	/* TODO 1: return up to ka_len bytes of ka_buf to userspace, honoring *ppos so a
	 * second read returns 0 (EOF).  hint: simple_read_from_buffer(). */
	return 0;
}

static ssize_t ka_write(struct file *f, const char __user *ubuf, size_t count, loff_t *ppos)
{
	/* TODO 2: copy up to BUFSZ bytes from userspace into ka_buf, set ka_len, and
	 * return the number of bytes stored.  hint: copy_from_user(). */
	return -EINVAL;
}

static long ka_ioctl(struct file *f, unsigned int cmd, unsigned long arg)
{
	/* TODO 3: if cmd == KA_GET_LEN, write ka_len (as an int) to the user pointer in
	 * arg and return 0; otherwise return -ENOTTY.  hint: copy_to_user(). */
	return -ENOTTY;
}

static const struct file_operations ka_fops = {
	.owner          = THIS_MODULE,
	.read           = ka_read,
	.write          = ka_write,
	.unlocked_ioctl = ka_ioctl,
	.llseek         = default_llseek,
};

static struct miscdevice ka_misc = {
	.minor = MISC_DYNAMIC_MINOR,
	.name  = DEV_NAME,
	.fops  = &ka_fops,
	.mode  = 0666,
};

static int __init ka_init(void)
{
	int ret = misc_register(&ka_misc);

	if (ret)
		pr_err("kernel-apprentice: misc_register failed: %d\n", ret);
	else
		pr_info("kernel-apprentice: /dev/%s ready\n", DEV_NAME);
	return ret;
}

static void __exit ka_exit(void)
{
	misc_deregister(&ka_misc);
}

module_init(ka_init);
module_exit(ka_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("kernel-apprentice");
MODULE_DESCRIPTION("CHALLENGE: implement a misc char device's read/write/ioctl.");
