// SPDX-License-Identifier: GPL-2.0
/*
 * test.c — the userspace acceptance test for /dev/ka-chardev. Built static and run
 * by the guest in ../check.sh. It writes a message, asks the device its length via
 * an ioctl, reads it back, and checks all three agree. Prints "TEST PASS" and exits
 * 0 only when the module's read/write/ioctl are correctly implemented.
 */
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>

#define KA_GET_LEN _IOR('K', 1, int)
#define DEV "/dev/ka-chardev"

int main(void)
{
	const char *msg = "kernel-apprentice";   /* 17 bytes */
	size_t mlen = strlen(msg);

	int fd = open(DEV, O_RDWR);
	if (fd < 0) { perror("open " DEV); return 1; }

	if (write(fd, msg, mlen) != (ssize_t)mlen) {
		fprintf(stderr, "FAIL: write did not store %zu bytes\n", mlen);
		return 2;
	}

	int len = -1;
	if (ioctl(fd, KA_GET_LEN, &len) != 0) { perror("FAIL: ioctl KA_GET_LEN"); return 3; }
	if (len != (int)mlen) {
		fprintf(stderr, "FAIL: ioctl length got %d, want %zu\n", len, mlen);
		return 4;
	}

	char buf[64] = {0};
	lseek(fd, 0, SEEK_SET);
	ssize_t r = read(fd, buf, sizeof(buf));
	if (r != (ssize_t)mlen || memcmp(buf, msg, mlen) != 0) {
		fprintf(stderr, "FAIL: read back %zd bytes '%s'\n", r, buf);
		return 5;
	}

	close(fd);
	printf("TEST PASS: write/read/ioctl all agree on \"%s\" (%zu bytes)\n", msg, mlen);
	return 0;
}
