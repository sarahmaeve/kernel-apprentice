// SPDX-License-Identifier: GPL-2.0
/*
 * trigger.c — call getpid via the RAW syscall so it always enters the kernel.
 *
 * glibc's getpid() can be cached or served without a real trap; syscall() goes
 * straight through the door, so whatever ftrace probe we attached to the live
 * kernel is guaranteed to fire. A few calls so the trace is easy to spot.
 * Used by ../check.sh.
 */
#include <stdio.h>
#include <unistd.h>
#include <sys/syscall.h>

int main(void)
{
	long pid = 0;
	int i;

	for (i = 0; i < 5; i++)
		pid = syscall(SYS_getpid);

	printf("trigger: syscall(SYS_getpid) = %ld (x5)\n", pid);
	return 0;
}
